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
use strict; use warnings;

package SIPTunnel::Mediator::Session;
use Digest::MD5 qw/md5_hex/;
use SIPTunnel::Spec;
use Sys::Syslog qw(syslog);
use URL::Encode::XS qw/url_encode_utf8/;

my %sip_socket_map;
my %http_socket_map;

sub new {
    my ($class, $config, $sip_socket) = @_;

    my $self = {
        seskey => md5_hex(time."$$".rand()),
        sip_socket => $sip_socket,
        http_path => $config->{http_path}
    };

    my %http_args = (
        Host => $config->{http_address},
        PeerPort => $config->{http_port},
        KeepAlive => 1 # true
    );

    if ($config->{http_proto} eq 'http') {
        $self->{http_socket} = Net::HTTP::NB->new(%http_args);
    } else {
        $self->{http_socket} = Net::HTTPS::NB->new(%http_args);
    }

    $self = bless($self, $class);

    $sip_socket_map{$self->sip_socket} = $self;
    $http_socket_map{$self->http_socket} = $self;

    return $self;
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

sub read_sip_socket {
    my $self = shift;
    my $sclient = $self->sip_socket_str;

    local $/ = "\015";
    my $sip_txt = readline($self->sip_socket);

    unless ($sip_txt) {
        syslog(LOG_DEBUG => "SIP client [$sclient] disconnected");
        return 0;
    }

    syslog(LOG_DEBUG => "INPUT [$sclient] $sip_txt");

    my $msg = SIPTunnel::Message->from_sip($sip_txt);

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
    # is called and no data is there, it will raise an error.
    # Note that $sock->connected still shows as true in such cases.
    eval { ($code, $mess, %headers) = $sock->read_response_headers };

    if ($@) {
        syslog(LOG_DEBUG => "[$sclient] HTTP server keepalive timed out.");
        return 0;
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

    my $msg = SIPTunnel::Message->from_json($content);

    return $self->relay_sip_response($msg);
}

sub relay_sip_response {
    my ($self, $msg) = @_;
    my $sclient = $self->sip_socket_str;

    my $sip_txt = $msg->to_sip;

    syslog(LOG_DEBUG => "OUTPUT [$sclient] $sip_txt");

    $self->sip_socket->print($sip_txt);

    return 1;
}

package SIPTunnel::Mediator;
use Sys::Syslog qw(syslog openlog);
use Net::HTTP::NB;
use Net::HTTPS::NB;
use Socket;
use IO::Select;
use IO::Socket::INET;
use SIPTunnel::Spec;
use SIPTunnel::Message;

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

    openlog('SIPTunnel', 'pid', $self->config->{syslog_facility});

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

            if ($socket == $server_socket) {

                my $client = $server_socket->accept;

                syslog(LOG_DEBUG => "New client connection: ".$client->peerhost);

                $session =
                    SIPTunnel::Mediator::Session->new($self->config, $client);

                $sip_socket_map{$client} =
                    $http_socket_map{$session->http_socket} = $session;

                #$client->autoflush(1);
                $select->add($client);
                $select->add($session->http_socket);

            } elsif ($session = 
                SIPTunnel::Mediator::Session->find_by_sip_socket($socket)) {

                my $paddr = $session->sip_socket->peerhost;

                unless ($session->read_sip_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->cleanup;
                }

            } elsif ($session = 
                SIPTunnel::Mediator::Session->find_by_http_socket($socket)) {

                my $paddr = $session->sip_socket->peerhost;

                unless ($session->read_http_socket) {
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->cleanup;
                }
            }
        }
    }
}

1;

