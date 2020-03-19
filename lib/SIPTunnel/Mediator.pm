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

sub new {
    my ($class, $config, $sip_socket) = @_;

    my $self = {
        seskey => md5_hex(time."$$".rand()),
        sip_socket => $sip_socket,
        http_path => $config->{http_path}
    };

    my %http_args = (
        Host => $config->{http_address},
        Port => $config->{http_port}
    );

    if ($config->{http_proto} eq 'http') {
        $self->{http_socket} = Net::HTTP::NB->new(%http_args);
    } else {
        $self->{http_socket} = Net::HTTPS::NB->new(%http_args);
    }

    return bless($self, $class);
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

sub read_sip_socket {
    my $self = shift;

    local $/ = "\015";
    my $sip_txt = readline($self->sip_socket); 

    unless ($sip_txt) {
        print "SIP client disconnected\n";
        return 0;
    }

    print "read SIP text: $sip_txt\n";

    my $msg = SIPTunnel::Message->from_sip($sip_txt);

    print $msg->to_json . "\n";

    return 1;
}

sub read_http_socket {
    my $self = shift;
}


package SIPTunnel::Mediator;
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

    my %sip_socket_map;
    my %http_socket_map;

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

    while (my @ready = $select->can_read) {

        for my $socket (@ready) {
            my $session;

            if ($socket == $server_socket) {

                my $client = $server_socket->accept;

                print "New client connection: $client\n";

                $session = 
                    SIPTunnel::Mediator::Session->new($self->config, $client);

                $sip_socket_map{$client} = 
                    $http_socket_map{$session->http_socket} = $session;

                $client->autoflush(1);
                $select->add($client);

            } elsif ($session = $sip_socket_map{$socket}) {
                unless ($session->read_sip_socket) {
                    delete $sip_socket_map{$session->sip_socket};
                    delete $http_socket_map{$session->http_socket};
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->sip_socket->close;
                    $session->http_socket->close;

                }

            } elsif ($session = $http_socket_map{$socket}) {
                unless ($session->read_http_socket) {
                    delete $sip_socket_map{$session->sip_socket};
                    delete $http_socket_map{$session->http_socket};
                    $select->remove($session->sip_socket);
                    $select->remove($session->http_socket);
                    $session->sip_socket->close;
                    $session->http_socket->close;
                }
            }
        }
    }
}

1;

