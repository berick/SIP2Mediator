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
package SIPTunnel::Spec::Message;
use strict; use warnings;

# code => spec map of registered message specs
my %known_messages;

sub new {
    my ($class, $code, $label, $fixed_fields) = @_;

    my $self = {
        code => $code, 
        label => $label, 
        fixed_fields => $fixed_fields || []
    };

    return $known_messages{$code} = bless($self, $class);
}

sub code {
    my $self = shift;
    return $self->{code};
}

sub label {
    my $self = shift;
    return $self->{label};
}

sub fixed_fields {
    my $self = shift;
    return $self->{fixed_fields};
}

sub find_by_code {
    my ($class, $code) = @_;

    my $spec = $known_messages{$code};

    # Nothing we can do with unknown message types.
    warn "No such SIP2 message code = $code\n" unless $spec;

    return $spec;
}

1;
