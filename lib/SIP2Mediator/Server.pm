# -----------------------------------------------------------------------
# Copyright (C) 2020 King County Library System
# Bill Erickson <berickxx@gmail.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# Models a single SIP client connection and its paired ILS back-end.
# -----------------------------------------------------------------------
package SIP2Mediator::Server::Session;
use strict; use warnings;
use Digest::MD5 qw/md5_hex/;
use SIP2Mediator::Spec;
use Sys::Syslog qw(syslog);

my %sip_socket_map;

sub new {
    my ($class, $config, $sip_socket) = @_;

    my $self = {
        seskey => md5_hex(time."$$".rand()),
        sip_socket => $sip_socket,
        config => $config
    };

    $self->{sip_socket_str} = sprintf('%s:%s', 
        $sip_socket->peerhost, $sip_socket->peerport);

    $self = bless($self, $class);

    $sip_socket_map{$self->sip_socket} = $self;

    my $count = scalar(keys(%sip_socket_map));

    my $sclient = $self->sip_socket_str;

    syslog(LOG_INFO => "[$sclient] New SIP client connecting; ".
        "total=$count; key=".substr($self->seskey, 0, 10));

    return $self;
}

sub config {
    my $self = shift;
    return $self->{config};
}

sub from_sip_socket {
    my ($class, $socket) = @_;
    return $sip_socket_map{$socket};
}

sub cleanup_sip_socket {
    my $self = shift;
    my $skip_xs = shift;
    my $sclient = $self->sip_socket_str;

    syslog(LOG_DEBUG => "[$sclient] cleaning up sip socket ".$self->seskey);

    if ($self->sip_socket) {

        $self->sip_socket->shutdown(2);
        $self->sip_socket->close;
        delete $sip_socket_map{$self->sip_socket};
        delete $self->{sip_socket};

    } else {
        # Should never get here, but avoid crashing the server in case.
        syslog(LOG_WARNING => "[$sclient] SIP socket disapeared ".$self->seskey);
    }
}

sub seskey {
    my $self = shift;
    return $self->{seskey};
}

sub sip_socket {
    my $self = shift;
    return $self->{sip_socket};
}

sub sip_socket_str {
    my ($self) = @_;
    return $self->{sip_socket_str};
}

sub dead {
    my ($self, $value) = @_;
    $self->{dead} = $value if defined $value;
    return $self->{dead};
}

# -----------------------------------------------------------------------
# Listens for new SIP client connections and routes requests and 
# responses to the appropriate end points.
# -----------------------------------------------------------------------
package SIP2Mediator::Server;
use strict; use warnings;
use Sys::Syslog 
    qw(syslog openlog setlogmask LOG_UPTO LOG_DEBUG LOG_INFO LOG_WARNING LOG_ERR);
use Socket;
use IO::Select;
use IO::Socket::INET;
use SIP2Mediator::Spec;
use SIP2Mediator::Message;
use Encode;
use Unicode::Normalize;

# TODO MAKE THIS DYNAMIC
use SIP2Mediator::Plugins::EvergreenILS;

my $shutdown_requested = 0;
$SIG{USR1} = sub { $shutdown_requested = 1; };

sub new {
    my ($class, $config) = @_;

    my $self = {config => $config};

    # TODO MAKE THIS DYNAMIC
    $self->{plugin} = SIP2Mediator::Plugins::EvergreenILS->new;

    die "Cannot init SIP Plugin\n" unless $self->{plugin}->init($config);

    return bless($self, $class);
}

sub config {
    my $self = shift;
    return $self->{config};
}

sub plugin {
    my $self = shift;
    return $self->{plugin};
}

sub cleanup {
    my $self = shift;
    syslog(LOG_INFO => 'Cleaning up and exiting');

    for my $sock (keys %sip_socket_map) {
        my $ses = SIP2Mediator::Server::Session->from_sip_socket($sock);
        $ses->cleanup_sip_socket if $ses;
    }

    $self->plugin->shutdown;

    exit(0);
}

sub client_count {
    my $self = shift;
    return scalar(keys(%sip_socket_map));
}

sub loglevel {
    my $self = shift;

    # Surely there's a simpler way to do this?
    my $l = $self->config->{syslog_level};

    return LOG_DEBUG if $l eq 'LOG_DEBUG';
    return LOG_WARNING if $l eq 'LOG_WARNING';
    return LOG_ERR if $l eq 'LOG_ERR';
    return LOG_INFO;
}

sub listen {
    my $self = shift;

    openlog('SIP2Mediator', 'pid', $self->config->{syslog_facility});
    setlogmask(LOG_UPTO($self->loglevel));

    my $server_socket = IO::Socket::INET->new(
        Proto => 'tcp',
        LocalAddr => $self->config->{sip_address},
        LocalPort => int($self->config->{sip_port}),
        Reuse => 1,
        Listen => SOMAXCONN
    );

    die "Cannot create SIP socket: $!\n" unless $server_socket;

    my $select = IO::Select->new;
    $select->add($server_socket);
    $select->add($self->plugin->socket);

    syslog(LOG_INFO => 'Ready for clients...');

    # Incremented with each SIP request, decremented with each response
    # returned.  When the value is zero, no requests are in flight.
    # Each request will be met with exactly one response.
    my $in_flight = 0;

    while (1) {

        if ($shutdown_requested) {
            syslog(LOG_INFO => 'Shutdown requested...');

            if ($server_socket) { 
                # Shut down the server socket to prevent new connections.
                # Client sockets will be shut down once it's safe to
                # complete the graceful shutdown.
                $select->remove($server_socket);
                $server_socket->shutdown(2);
                $server_socket->close;
                $server_socket = undef;
            }

            # cleanup calls exit
            $self->cleanup if ($in_flight == 0 || $select->count == 0);

            syslog(LOG_DEBUG => 
                "Waiting for requests to settle in shutdown. in_flight=$in_flight");
        }

        # Block until we have work to do.
        my @ready = $select->can_read;

        if (!@ready) {
            syslog(LOG_ERR => "Select failed: $!.  Closing server to prevent looping");
            exit(1);
        }

        for my $socket (@ready) {
            my $session;
            my $plugin_resp;

            #syslog(LOG_DEBUG => "Socket active at peerport " . 
            #    $socket->peerport . " and local port " . $socket->sockport);

            if ($socket == $server_socket) { # new SIP client

                my $client = $server_socket->accept;

                if ($self->config->{max_clients} &&
                    $self->client_count >= $self->config->{max_clients}) {

                    $client->shutdown(2);
                    $client->close;
                    syslog(LOG_WARNING => 
                        "SIP client rejected because the server has ".
                        "reached max_clients=".$self->config->{max_clients});

                    next;
                }

                $session =
                    SIP2Mediator::Server::Session->new($self->config, $client);

                $select->add($client);

            } elsif ($session = # new SIP request
                SIP2Mediator::Server::Session->from_sip_socket($socket)) {

                if ($session->dead || !$self->relay_sip_request($session)) {
                    $select->remove($session->sip_socket);

                    # This will send the 'XS' end-session message
                    $session->cleanup_sip_socket;

                } else {
                    $in_flight++;
                }

            } elsif ($plugin_resp = $self->plugin->recv) {
                $in_flight--;

                $session = $plugin_resp->{session};
                my $sip_hash = $plugin_resp->{sip_hash};

                if (!$self->relay_sip_response($session, $sip_hash)) {
                    $select->remove($session->sip_socket);
                    $session->cleanup_sip_socket;
                }
            }
        }
    }
}

# Sends a SIP request from the SIP client to the ILS.
sub relay_sip_request {
    my $self = shift;
    my $session = shift;
    my $sclient = $session->sip_socket_str;

    local $SIG{'PIPE'} = sub {                                                 
        syslog(LOG_DEBUG => "[$sclient] SIP client disconnected prematurely.");
        $session->dead(1);
    };    

    local $/ = SIP2Mediator::Spec::LINE_TERMINATOR;
    my $sip_txt = decode_utf8(readline($session->sip_socket));

    unless ($sip_txt) {
        syslog(LOG_DEBUG => "[$sclient] SIP client disconnected; ".
            "key=".substr($session->seskey, 0, 10));
        return 0;
    }

    $sip_txt = SIP2Mediator::Message->clean_sip_packet($sip_txt);

    syslog(LOG_INFO => "[$sclient] INPUT $sip_txt");

    # Client sent an empty request.  Ignore it.
    return 1 unless $sip_txt;

    my $msg = SIP2Mediator::Message->from_sip($sip_txt);

    if (!$msg) {
        syslog(LOG_WARNING => "[$sclient] sent invalid SIP: $sip_txt");
        return 0;
    }

    return $self->plugin->send($session, $msg->to_hash);
}

# Sends the SIP message response received from the ILS to the SIP client.
sub relay_sip_response {
    my ($self, $session, $sip_hash) = @_;
    my $sclient = $session->sip_socket_str;

    if (!$session->sip_socket) {
        # Should never get here, but avoid crashing the server in case.
        syslog(LOG_WARNING => "[$sclient] SIP socket disapeared ".$session->seskey);
        return 0;
    }

    if (!$sip_hash) {
        syslog('LOG_ERR', 
            "[$sclient] SIP Plugin returned no data");
        return 0;
    }

    my $sip_msg = SIP2Mediator::Message->from_hash($sip_hash);

    if (!$sip_msg) {
        syslog('LOG_ERR', 
            "[$sclient] SIP Plugin returned unusable data"); # TODO log json
        return 0;
    }

    my $sip_txt = $sip_msg->to_sip;

    syslog(LOG_INFO => "[$sclient] OUTPUT $sip_txt");

    local $SIG{'PIPE'} = sub {                                                 
        syslog(LOG_DEBUG => "SIP client [$sclient] disconnected prematurely");
        $session->dead(1);
    };    

    if ($self->config->{ascii}) {
        # Normalize and strip combining characters.
        $sip_txt = NFD($sip_txt);
        $sip_txt =~ s/\pM+//og;
        $sip_txt = encode('ascii', $sip_txt);
    } else {
        $sip_txt = encode_utf8($sip_txt);
    }

    $session->sip_socket->print($sip_txt);

    return 1;
}



1;

