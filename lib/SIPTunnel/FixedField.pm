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
package SIPTunnel::FixedField;
use strict; use warnings;
use SIPTunnel::Field;
use base qw/SIPTunnel::Field/;

sub to_sip {
    my $self = shift;
    return SIPTunnel::Spec::sip_string($self->value);
}

sub to_str {
    my $self = shift;

    my $spaces = 
        SIPTunnel::Spec::STRING_COLUMN_PAD - length($self->spec->label);

    my $value = SIPTunnel::Spec::sip_string($self->value);

    return sprintf('%s %s %s', $self->spec->label, ' ' x $spaces, $value);
}

1;

