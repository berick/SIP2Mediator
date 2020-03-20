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

my %sip_socket_map;
my %http_socket_map;

sub new {
    my ($class, $config, $sip_socket) = @_;

    my $self = {
        seskey => md5_hex(time."$$".rand()),
        sip_socket => $sip_socket,
        http_path => $config->{http_path},
        http_port => $config->{http_port},
        http_proto => $config->{http_proto},
        http_host => $config->{http_host}
    };

    $self = bless($self, $class);

    $sip_socket_map{$self->sip_socket} = $self;
    $self->create_http_socket;

    syslog(LOG_DEBUG => 
        "New SIP client connecting from ".$self->sip_socket_str);

    return $self;
}

sub create_http_socket {
    my $self = shift;
    $self->http_dead(0);

    if (my $sock = $self->http_socket) { # Clean up the old socket
        syslog(LOG_DEBUG => 'Closing exhausted HTTP socket');
        delete $http_socket_map{$sock};    
        delete $self->{http_socket};
        $sock->shutdown(2);
        $sock->close;
    }

    my %http_args = (
        Host => $self->{http_host},
        PeerPort => $self->{http_port},
        KeepAlive => 1 # true
    );

    if ($self->{http_proto} eq 'http') {
        $self->{http_socket} = Net::HTTP::NB->new(%http_args);
    } else {
        $self->{http_socket} = Net::HTTPS::NB->new(%http_args);
    }

    $http_socket_map{$self->http_socket} = $self;
}

sub find_by_sip_socket {
    my ($class, $socket) = @_;
    return $sip_socket_map{$socket};
}

sub find_by_http_socket {
    my ($class, $socket) = @_;
    return $http_socket_map{$socket};
}

sub cleanup {
    my $self = shift;
    delete $sip_socket_map{$self->sip_socket};
    delete $http_socket_map{$self->http_socket};
    $self->sip_socket->shutdown(2);
    $self->http_socket->shutdown(2);
    $self->sip_socket->close;
    $self->http_socket->close;
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

sub http_path {
    my $self = shift;
    return $self->{http_path};
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
        syslog(LOG_DEBUG => "SIP client [$sclient] disconnected prematurely.");
        $self->dead(1);
    };    

    local $/ = SIP2Mediator::Spec::LINE_TERMINATOR;
    my $sip_txt = readline($self->sip_socket);

    unless ($sip_txt) {
        syslog(LOG_DEBUG => "SIP client [$sclient] disconnected");
        return 0;
    }

    chomp($sip_txt);

    $sip_txt =~ s/\r|\n//g;         # Remove newlines
    $sip_txt =~ s/^\s*[^A-z0-9]+//g; # Remove preceding junk
    $sip_txt =~ s/[^A-z0-9]+$//g;    # Remove trailing junk

    syslog(LOG_DEBUG => "[$sclient] INPUT $sip_txt");

    # Client sent an empty request.  Ignore it.
    return 1 unless $sip_txt;

    my $msg = SIP2Mediator::Message->from_sip($sip_txt);

    return $self->relay_sip_request($msg);
}

sub relay_sip_request {
    my ($self, $msg) = @_;

    my $post = sprintf('session=%s&message=%s',
        $self->seskey, url_encode_utf8($msg->to_json));

    #syslog(LOG_INFO => "POST: $post");

    $self->http_socket->write_request(POST => $self->http_path, $post);

    return 1;
}

sub read_http_socket {
    my $self = shift;
    my $sock = $self->http_socket;
    my $sclient = $self->sip_socket_str;

    my ($code, $mess, %headers);

    # When the HTTP server closes the connection as a result of a
    # KeepAlive timeout expiration, it will appear to IO::Select
    # that data is ready for reading.  However, if read_response_headers
    # is called and no data is there, Net::HTTP::NB will raise an error.
    # Catch the error and 
    # Note that $sock->connected still shows as true in such cases.
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

sub new {
    my ($class, $config) = @_;

    my $self = {config => $config};

    return bless($self, $class);
}

sub config {
    my $self = shift;
    return $self->{config};
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

    while (my @ready = $select->can_read) {

        for my $socket (@ready) {
            my $session;

            if ($socket == $server_socket) { # new SIP client

                my $client = $server_socket->accept;

                $session =
                    SIP2Mediator::Server::Session->new($self->config, $client);

                $sip_socket_map{$client} =
                    $http_socket_map{$session->http_socket} = $session;

                $select->add($client);
                $select->add($session->http_socket);

            } elsif ($session = # new SIP request
                SIP2Mediator::Server::Session->find_by_sip_socket($socket)) {

                if ($session->dead || !$session->read_sip_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->cleanup;
                }

            } elsif ($session = # new HTTP response
                SIP2Mediator::Server::Session->find_by_http_socket($socket)) {

                if ($session->dead || !$session->read_http_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->cleanup;
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

