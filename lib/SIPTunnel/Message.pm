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
package SIPTunnel::Message;
use strict; use warnings;
use Locale::gettext;
use JSON::XS;
use SIPTunnel::Spec;
use SIPTunnel::Spec::FixedField;
use SIPTunnel::Spec::Field;
use SIPTunnel::Spec::Message;
use SIPTunnel::FixedField;
use SIPTunnel::Field;

my $json = JSON::XS->new;
$json->ascii(1);
$json->allow_nonref(1);

sub new {
    my ($class, %args) = @_;

    my $self = {
        spec => $args{spec},
        fields => $args{fields} || [],
        fixed_fields => $args{fixed_fields} || []
    };

    return bless($self, $class);
}

sub spec {
    my $self = shift;
    return $self->{spec};
}

sub fixed_fields {
    my $self = shift;
    return $self->{fixed_fields};
}

sub fields {
    my $self = shift;
    return $self->{fields};
}


sub add_field {
    my ($self, $spec, $value) = @_;
    push(@{$self->{fields}}, SIPTunnel::Field->new($spec, $value)); 
}

sub maybe_add_field {
    my ($self, $spec, $value) = @_;
    $self->add_field($spec, $value) if defined $value;
}

# Turns a Message into a SIP string.
sub to_sip {
    my $self = shift;

    my $txt = $self->spec->code;

    $txt .= $_->to_sip for @{$self->fixed_fields};

    $txt .= $_->to_sip for @{$self->fields};

    return $txt;
}

# Turns a SIP string into a Message
sub from_sip {
    my ($class, $msg_sip) = @_;

    my $msg = SIPTunnel::Message->new;

    # strip the line separator
    my $len = length($msg_sip) - length(SIPTunnel::Spec::LINE_TERMINATOR);
    my $txt = substr($msg_sip, 0, $len);

    $msg->{spec} = SIPTunnel::Spec::Message->find_by_code(substr($txt, 0, 2));

    $txt = substr($txt, 2);

    for my $ffspec (@{$msg->spec->fixed_fields}) {
        my $value = substr($txt, 0, $ffspec->length);
        $txt = substr($txt, $ffspec->length);
        push(@{$msg->fixed_fields}, 
            SIPTunnel::FixedField->new($ffspec, $value));
    }

    # Some messages only have fixed fields.
    return $msg unless $txt;

    my @parts = split(/\|/, $txt);

    for my $part (@parts) {
        last unless $part;
        my $fspec = SIPTunnel::Spec::Field->find_by_code(substr($part, 0, 2));
        push(@{$msg->fields}, SIPTunnel::Field->new($fspec, substr($part, 2)));
    }

    return $msg;
}

sub to_json {
    my $self = shift;

    my @ffields;
    my @fields;

    push(@ffields, SIPTunnel::Spec::sip_string($_->value)) 
        for @{$self->fixed_fields};

    push(@fields, {$_->spec->code => SIPTunnel::Spec::sip_string($_->value)}) 
        for @{$self->fields};

    return $json->encode({
        code => $self->spec->code,
        fields => \@fields,
        fixed_fields => \@ffields
    });
}

sub from_json {
    my ($class, $msg_json) = @_;

    return undef unless $msg_json;

    my $hash = $json->decode($msg_json);

    # Start with a SIP message string which contains only the 
    # message code and fixed fields.
    my $txt = sprintf('%s%s%s',
        $hash->{code},
        join('', @{$hash->{fixed_fields}}),
        SIPTunnel::Spec::LINE_TERMINATOR
    );

    my $msg = $class->from_sip($txt);

    # Then add the variable length Fields
    
    return $msg unless $hash->{fields};

    for my $field (@{$hash->{fields}}) {
        for my $code (keys(%$field)) { # will only be one
            my $value = $field->{$code};
            my $spec = SIPTunnel::Spec::Field->find_by_code($code);
            $msg->add_field($spec, $value);
        }
    }
            
    return $msg;
}

sub to_str {
    my $self = shift;

    my $txt = sprintf("[%s] %s\n", $self->spec->code, $self->spec->label);

    $txt .= $_->to_str . "\n" for @{$self->fixed_fields};
    $txt .= $_->to_str . "\n" for @{$self->fields};

    return $txt;
}

1;
