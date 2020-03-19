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
package SIPTunnel::Spec::FixedField;
use strict; use warnings;
use Locale::gettext;

sub new {
    my ($class, $length, $label) = @_;

    my $self = {
        length => $length, 
        label => $label
    };

    return bless($self, $class);
}

sub length {
    my $self = shift;
    return $self->{length};
}

sub label {
    my $self = shift;
    return $self->{label};
}

1;

