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
# Models a single SIP client connection and its paired HTTP back-end.
# -----------------------------------------------------------------------
package SIP2Mediator::Server::Session;
use strict; use warnings;
use Digest::MD5 qw/md5_hex/;
use SIP2Mediator::Spec;
use Sys::Syslog qw(syslog);
use URL::Encode::XS qw/url_encode_utf8/;
use Encode;
use Unicode::Normalize;

my %sip_socket_map;
my %http_socket_map;

sub new {
    my ($class, $config, $sip_socket) = @_;

    my $self = {
        seskey => md5_hex(time."$$".rand()),
        sip_socket => $sip_socket,
        config => $config,
        prev_sip_message => undef
    };

    $self = bless($self, $class);

    $sip_socket_map{$self->sip_socket} = $self;
    $self->create_http_socket;

    my $count = scalar(keys(%sip_socket_map));

    my $sclient = $self->sip_socket_str;
    syslog(LOG_DEBUG => "[$sclient] New SIP client connecting; total=$count");

    return $self;
}

sub prev_sip_message {
    my $self = shift;
    my $prev = shift;
    $self->{prev_sip_message} = $prev if defined $prev;
    return $self->{prev_sip_message};
}

sub config {
    my $self = shift;
    return $self->{config};
}

sub create_http_socket {
    my $self = shift;
    $self->http_dead(0);

    if (my $sock = $self->http_socket) { # Clean up the old socket
        my $sclient = $self->sip_socket_str;
        syslog(LOG_DEBUG => "[$sclient] Closing exhausted HTTP socket");
        delete $http_socket_map{$sock};    
        delete $self->{http_socket};
        $sock->shutdown(2);
        $sock->close;
    }

    my %http_args = (
        Host => $self->config->{http_host},
        PeerPort => $self->config->{http_port},
        KeepAlive => 1 # true
    );

    if ($self->config->{http_proto} eq 'http') {
        $self->{http_socket} = Net::HTTP::NB->new(%http_args);
    } else {
        $self->{http_socket} = Net::HTTPS::NB->new(%http_args);
    }

    my $sclient = $self->sip_socket_str;
    syslog(LOG_DEBUG => 
        "[$sclient] SIP client using HTTP(S) with local port " . 
        $self->http_socket->sockport);

    $http_socket_map{$self->http_socket} = $self;

    if ($self->prev_sip_message) {
        syslog(LOG_DEBUG => 
            "[$sclient] Re-sending SIP request after HTTP timeout");
        $self->relay_sip_request($self->prev_sip_message);
        $self->prev_sip_message(0);
    }
}

sub from_sip_socket {
    my ($class, $socket) = @_;
    return $sip_socket_map{$socket};
}

sub from_http_socket {
    my ($class, $socket) = @_;
    return $http_socket_map{$socket};
}

sub cleanup {
    my $self = shift;

    delete $sip_socket_map{$self->sip_socket};
    delete $http_socket_map{$self->http_socket};

    if ($self->http_socket) {
        # Let the HTTP backend know we are shutting down so it can
        # clean up any session data.
        my $sclient = $self->sip_socket_str;
        syslog(LOG_DEBUG => 
            "[$sclient] Sending End Session message to HTTP backend");

        $self->relay_sip_request(
            SIP2Mediator::Message->from_hash({code => 'XS'}));
    }

    $self->sip_socket->shutdown(2);
    $self->http_socket->shutdown(2);
    $self->sip_socket->close;
    $self->http_socket->close;
    delete $self->{http_socket};
    delete $self->{sip_socket};
}

sub seskey {
    my $self = shift;
    return $self->{seskey};
}

sub sip_socket {
    my $self = shift;
    return $self->{sip_socket};
}

sub http_socket {
    my $self = shift;
    return $self->{http_socket};
}

sub sip_socket_str {
    my ($self) = @_;
    my $s = $self->sip_socket;
    return sprintf('%s:%s', $s->peerhost, $s->peerport);
}

sub dead {
    my ($self, $value) = @_;
    $self->{dead} = $value if defined $value;
    return $self->{dead};
}

# True if the HTTP connection is no longer viable.
sub http_dead {
    my ($self, $value) = @_;
    $self->{http_dead} = $value if defined $value;
    return $self->{http_dead};
}

sub read_sip_socket {
    my $self = shift;
    my $sclient = $self->sip_socket_str;

    local $SIG{'PIPE'} = sub {                                                 
        syslog(LOG_DEBUG => "[$sclient] SIP client disconnected prematurely.");
        $self->dead(1);
    };    

    local $/ = SIP2Mediator::Spec::LINE_TERMINATOR;
    my $sip_txt = decode_utf8(readline($self->sip_socket));

    unless ($sip_txt) {
        syslog(LOG_DEBUG => "[$sclient] SIP client disconnected");
        return 0;
    }

    $sip_txt = SIP2Mediator::Message->clean_sip_packet($sip_txt);

    syslog(LOG_DEBUG => "[$sclient] INPUT $sip_txt");

    # Client sent an empty request.  Ignore it.
    return 1 unless $sip_txt;

    my $msg = SIP2Mediator::Message->from_sip($sip_txt);

    if (!$msg) {
        syslog(LOG_DEBUG => "[$sclient] sent invalid SIP: $sip_txt");
        return 0;
    }

    $self->prev_sip_message($msg);

    return $self->relay_sip_request($msg);
}

sub relay_sip_request {
    my ($self, $msg) = @_;

    my $post = sprintf('session=%s&message=%s',
        $self->seskey, url_encode_utf8($msg->to_json));

    #syslog(LOG_INFO => "POST: $post");

    $self->http_socket->write_request(POST => $self->config->{http_path}, $post);

    return 1;
}

sub read_http_socket {
    my $self = shift;
    my $sock = $self->http_socket;
    my $sclient = $self->sip_socket_str;

    my ($code, $mess, %headers);

    # When the HTTP server closes the connection as a result of a
    # KeepAlive timeout expiration, it will appear to IO::Select that
    # data is ready for reading.  However, if read_response_headers is
    # called and no data is there, Net::HTTP::NB will raise an error.
    # Catch the error and mark the current HTTP socket as dead so a new
    # one can be created. Note that $sock->connected still shows as
    # true in such cases.
    eval { ($code, $mess, %headers) = $sock->read_response_headers };

    if ($@) {
        $self->http_dead(1);
        syslog(LOG_DEBUG => "[$sclient] HTTP server keepalive timed out.");
        return 1; # not an error condition
    }

    if ($code ne '200') {
        syslog(LOG_ERR => 
            "[$sclient] HTTP replied with error code: $code => $mess");
        return 0;
    }

    my ($content, $buf);

    while (1) {

        my $n = $sock->read_entity_body($buf, 1024);

        unless (defined $n) {
            syslog(LOG_ERR => "[$sclient] HTTP read error occured: $!");
            return 0;
        }

        last if $n == 0; # done reading

        #syslog(LOG_DEBUG => "[$sclient] HTTP read returned $n bytes");

        $content .= $buf;
    }

    #syslog(LOG_DEBUG => "[$sclient] HTTP response: $content");

    my $msg = SIP2Mediator::Message->from_json($content);

    if (!$msg) {
        syslog('LOG_ERR', "SIP HTTP backend returned unusable data: $content");
        # treat this as a non-fatal condition.
        return 1;
    }

    return $self->relay_sip_response($msg);
}

sub relay_sip_response {
    my ($self, $msg) = @_;
    my $sclient = $self->sip_socket_str;

    my $sip_txt = $msg->to_sip;

    syslog(LOG_DEBUG => "[$sclient] OUTPUT $sip_txt");

    local $SIG{'PIPE'} = sub {                                                 
        syslog(LOG_DEBUG => "SIP client [$sclient] disconnected prematurely");
        $self->dead(1);
    };    

    if ($self->config->{ascii}) {
        # Normalize and strip combining characters.
        $sip_txt = NFD($sip_txt);
        $sip_txt =~ s/\pM+//og;
        $sip_txt = encode('ascii', $sip_txt);
    } else {
        $sip_txt = encode_utf8($sip_txt);
    }

    $self->sip_socket->print($sip_txt);

    return 1;
}

# -----------------------------------------------------------------------
# Listens for new SIP client connections and routes requests and 
# responses to the appropriate end points.
# -----------------------------------------------------------------------
package SIP2Mediator::Server;
use strict; use warnings;
use Sys::Syslog qw(syslog openlog);
use Net::HTTP::NB;
use Net::HTTPS::NB;
use Socket;
use IO::Select;
use IO::Socket::INET;
use SIP2Mediator::Spec;
use SIP2Mediator::Message;

my $shutdown_requested = 0;
$SIG{USR1} = sub { $shutdown_requested = 1; };

sub new {
    my ($class, $config) = @_;

    my $self = {config => $config};

    return bless($self, $class);
}

sub config {
    my $self = shift;
    return $self->{config};
}

sub cleanup {
    my $self = shift;
    syslog(LOG_INFO => 'Cleaning up and exiting');

    for my $sock (keys %sip_socket_map) {
        my $ses = SIP2Mediator::Server::Session->from_sip_socket($sock);
        $ses->cleanup if $ses;
    }

    exit(0);
}

sub client_count {
    my $self = shift;
    return scalar(keys(%sip_socket_map));
}

sub listen {
    my $self = shift;

    openlog('SIP2Mediator', 'pid', $self->config->{syslog_facility});

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

        for my $socket (@ready) {
            my $session;

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
                $select->add($session->http_socket);

            } elsif ($session = # new SIP request
                SIP2Mediator::Server::Session->from_sip_socket($socket)) {

                if ($session->dead || !$session->read_sip_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    # SIP client disconnected
                    $session->cleanup;

                } else {
                    $in_flight++;
                }

            } elsif ($session = # new HTTP response
                SIP2Mediator::Server::Session->from_http_socket($socket)) {

                if ($session->dead || !$session->read_http_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->cleanup;

                } else {
                    $in_flight--;
                }

                if ($session->http_dead) {
                    # Keepalive timed out.  Create a new connection and
                    # add it to our select pool.
                    $select->remove($session->http_socket);
                    $session->create_http_socket;
                    $select->add($session->http_socket);
                }
            }
        }
    }
}

1;

