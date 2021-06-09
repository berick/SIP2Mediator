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
package SIP2Mediator::Message;
use strict; use warnings;
use Locale::gettext;
use JSON::XS;
use Sys::Syslog qw(syslog);
use SIP2Mediator::Spec;
use SIP2Mediator::Field;
use SIP2Mediator::FixedField;

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
    push(@{$self->{fields}}, SIP2Mediator::Field->new($spec, $value)); 
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

    $txt .= $_->to_sip for 
        # Sort by spec code for consistent message format.
        sort {$a->spec->code cmp $b->spec->code}
        # Skip any fields that have no value.
        grep {defined $_->value} @{$self->fields};

    $txt .= SIP2Mediator::Spec::LINE_TERMINATOR;

    return $txt;
}


# Removes gunk from a SIP message pulled directly from the socket.
sub clean_sip_packet {
    my ($class, $txt) = @_;
    chomp($txt);                 # remove line terminator
    $txt =~ s/\r|\n//g;          # Remove newlines
    $txt =~ s/^\s*[^A-z0-9]+//g; # Remove preceding junk
    $txt =~ s/[^A-z0-9]+$//g;    # Remove trailing junk
    return $txt;
}


# Turns a SIP string into a Message
# Assumes the final line terminator character has been removed.
sub from_sip {
    my ($class, $txt) = @_;

    my $msg = SIP2Mediator::Message->new;
    my $code = substr($txt, 0, 2);
    $msg->{spec} = SIP2Mediator::Spec::Message->find_by_code($code);

    if (!$msg->{spec}) {
        syslog('LOG_WARNING', "Unknown message type: '$code'");
        return undef;
    }

    $txt = substr($txt, 2);

    for my $ffspec (@{$msg->spec->fixed_fields}) {

        unless (defined $txt && length($txt) >= $ffspec->length) {
            syslog('LOG_WARNING', 
                "Fixed fields do not match spec for code $code.  Discarding");
            return undef;
        }

        my $value = substr($txt, 0, $ffspec->length);
        $txt = substr($txt, $ffspec->length);
        push(@{$msg->fixed_fields}, 
            SIP2Mediator::FixedField->new($ffspec, $value));
    }

    # Some messages only have fixed fields.
    return $msg unless $txt;

    my @parts = split(/\|/, $txt);

    for my $part (@parts) {
        last unless $part;
        my $fspec = SIP2Mediator::Spec::Field->find_by_code(substr($part, 0, 2));
        push(@{$msg->fields}, SIP2Mediator::Field->new($fspec, substr($part, 2)));
    }

    return $msg;
}

sub to_json {
    my $self = shift;

    my @ffields;
    my @fields;

    push(@ffields, SIP2Mediator::Spec->sip_string($_->value)) 
        for @{$self->fixed_fields};

    push(@fields, {$_->spec->code => SIP2Mediator::Spec->sip_string($_->value)}) 
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

    return $class->from_hash($hash);
}

# Message from our JSON format as a hash/object.
sub from_hash {
    my ($class, $hash) = @_;

    return undef unless $hash && $hash->{code};
    my @fixed_fields = @{$hash->{fixed_fields} || []};

    syslog('LOG_WARNING', "Fixed fields contain undefined values: @fixed_fields")
        if grep {!defined $_} @fixed_fields;

    # Start with a SIP message string which contains only the 
    # message code and fixed fields.
    my $txt = sprintf('%s%s', $hash->{code}, join('', @fixed_fields));

    my $msg = $class->from_sip($txt);

    return undef unless $msg;

    # Then add the variable length Fields
    
    return $msg unless $hash->{fields};

    for my $field (@{$hash->{fields}}) {
        for my $code (keys(%$field)) { # will only be one
            my $value = $field->{$code};
            my $spec = SIP2Mediator::Spec::Field->find_by_code($code);
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
    chomp($txt);

    return $txt;
}

1;
