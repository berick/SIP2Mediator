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
# Models a single SIP client connection.
# -----------------------------------------------------------------------
package SIP2Mediator::Client;
use strict; use warnings;
use Sys::Syslog qw(syslog openlog);
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

sub socket {
    my $self = shift;
    return $self->{socket};
}

sub connect {
    my $self = shift;

    openlog('SIP2Mediator', 'pid', $self->config->{syslog_facility});

    my $socket = IO::Socket::INET->new(
        Proto => 'tcp',
        PeerHost => $self->config->{sip_address},
        PeerPort => int($self->config->{sip_port})
    ) or die "Cannot create SIP socket: $!\n";

    $self->{socket} = $socket;
    return $self->socket->connected;
}

sub disconnect {
    my $self = shift;
    if ($self->socket) {
        $self->socket->shutdown(2);
        $self->socket->close;
        delete $self->{socket};
    }
}

sub send {
    my ($self, $msg) = @_;

    die "Socket is not connected\n"
        unless $self->socket && $self->socket->connected;

    my $sip_txt = $msg->to_sip;

    syslog(LOG_DEBUG => "OUTPUT $sip_txt");

    local $SIG{'PIPE'} = sub {
        syslog(LOG_DEBUG => "SIP server disconnected prematurely.");
        $self->disconnect;
    };

    $self->socket->print($sip_txt);
}

sub recv {
    my $self = shift;

    die "Socket is not connected\n"
        unless $self->socket && $self->socket->connected;

    local $SIG{'PIPE'} = sub {
        syslog(LOG_DEBUG => "SIP server disconnected prematurely.");
        $self->disconnect;
    };

    local $/ = SIP2Mediator::Spec::LINE_TERMINATOR;
    my $sip_txt = readline($self->socket);

    unless ($sip_txt) {
        syslog(LOG_DEBUG => "SIP client disconnected");
        return undef;
    }

    $sip_txt = SIP2Mediator::Message->clean_sip_packet($sip_txt);

    syslog(LOG_DEBUG => "INPUT $sip_txt");

    # Client sent an empty request.  Ignore it.
    return undef unless $sip_txt;

    my $msg = SIP2Mediator::Message->from_sip($sip_txt);

    if (!$msg) {
        syslog(LOG_DEBUG => "Received invalid SIP: $sip_txt");
        return undef;
    }

    return $msg;
}

1;

