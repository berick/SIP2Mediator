# -----------------------------------------------------------------------
# Copyright (C) 2021 King County Library System
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
# Handles communication between SIP2Mediator and Evergreen ILS.
# -----------------------------------------------------------------------
package SIP2Mediator::Plugins::EvergreenILS;
use strict; use warnings;
use Sys::Syslog qw(syslog);
use OpenSRF::Transport::PeerHandle;
use OpenSRF::AppSession;
use OpenILS::Utils::Fieldmapper;

my $osrf_ses;

my @requests;

sub new {
    my $class = shift;
    return bless({}, $class);
}

sub init {
    my ($self, $config) = @_;

    OpenSRF::System->bootstrap_client(config_file => $config->{plugin_config});
    return 0 unless $self->socket;

    Fieldmapper->import(IDL => 
        OpenSRF::Utils::SettingsClient->new->config_value('IDL'));

    $osrf_ses = OpenSRF::AppSession->create('open-ils.sip2');

    return $self->socket ? 1 : 0;
}

# This must be a thing that can be passed to IO::Select.
sub socket {
    my $osrf_handle = OpenSRF::Transport::PeerHandle->retrieve;
    return undef unless $osrf_handle && $osrf_handle->connected;
    return $osrf_handle->socket;
}

sub send {
    my ($self, $sip_ses, $sip_hash) = @_;

    my $req = $osrf_ses->request(
        'open-ils.sip2.request', $sip_ses->seskey, $sip_hash);

    push(@requests, {sip_ses => $sip_ses, osrf_req => $req});

    return 1;
}

# Returns one response per call
sub recv {
    my $self = shift;

    for my $request (@requests) {
        my $osrf_req = $request->{osrf_req};

        next unless my $resp = $osrf_req->recv;

        @requests = 
            grep {$_->{osrf_req}->threadTrace != $osrf_req->threadTrace} @requests;

        if ($osrf_req->failed) {
            syslog('LOG_ERR', 
                "OpenSRF Request Failed:" . $osrf_req->failed->stringify);
            return undef;
        }

        return {
            session => $request->{sip_ses},
            sip_hash => $resp->content
        };
    }

    return undef;
}

sub shutdown {
    if (my $osrf_handle = OpenSRF::Transport::PeerHandle->retrieve) {
        $osrf_handle->disconnect;
    }
}

'Hello, Evergreen';

