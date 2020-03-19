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
package SIPTunnel::Spec::Field;
use strict; use warnings;

# code => spec map of registered fields
my %known_fields;

sub new {
    my ($class, $code, $label) = @_;
    my $self = {
        code => $code, 
        label => $label
    };
    
    return $known_fields{$code} = bless($self, $class);
}

sub code {
    my $self = shift;
    return $self->{code};
}

sub label {
    my $self = shift;
    return $self->{label};
}

# Returns the field spec for the given code.
# If no such field is known, a new field is registered using the code
# as the code and label.
sub find_by_code {
    my ($class, $code) = @_;
    my $spec = $known_fields{$code};

    if (!$spec) {
        # no spec found for the given code.  This can happen when
        # nonstandard fields are used (which is OK).  Create a new 
        # spec using the code as the label.
        $spec = SIPTunnel::Spec::Field->new($code, $code);
    }

    return $spec;
}

1;
