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
package SIP2Mediator::Spec::FixedField;
use strict; use warnings;

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


package SIP2Mediator::Spec::Field;
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
        $spec = SIP2Mediator::Spec::Field->new($code, $code);
    }

    return $spec;
}

package SIP2Mediator::Spec::Message;
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

# - Compiled SIP Fixed Field, Field, and Message Specifications and Constants -
package SIP2Mediator::Spec;
use strict; use warnings;
use Locale::gettext;

my $l = Locale::gettext->domain("SIP2Mediator");

use constant TEXT_ENCODING     => 'UTF-8';
use constant SIP_DATETIME      => '%Y%m%d    %H%M%S';
use constant LINE_TERMINATOR   => "\r";
use constant SOCKET_BUFSIZE    => 4096;
use constant STRING_COLUMN_PAD => 32; # for printing/debugging 

# Prepare a string value for adding to a SIP message string.
sub sip_string {
    my $value = shift;
    $value = defined $value ? "$value" : '';
    $value =~ s/\|//g;
    return $value;
}

# --- Fixed Field Definitions ----------------------------------------------

package FFSpec;
use strict; use warnings;

my $STSFF = 'SIP2Mediator::Spec::FixedField'; # shorthand

$FFSpec::date                = $STSFF->new(18, $l->get('transaction date'));
$FFSpec::ok                  = $STSFF->new(1,  $l->get('ok'));
$FFSpec::uid_algo            = $STSFF->new(1,  $l->get('uid algorithm'));
$FFSpec::pwd_algo            = $STSFF->new(1,  $l->get('pwd algorithm'));
$FFSpec::fee_type            = $STSFF->new(2,  $l->get('fee type'));
$FFSpec::payment_type        = $STSFF->new(2,  $l->get('payment type'));
$FFSpec::currency_type       = $STSFF->new(3,  $l->get('currency type'));
$FFSpec::payment_accepted    = $STSFF->new(1,  $l->get('payment accepted'));
$FFSpec::circ_status         = $STSFF->new(2,  $l->get('circulation status'));
$FFSpec::security_marker     = $STSFF->new(2,  $l->get('security marker'));
$FFSpec::language            = $STSFF->new(3,  $l->get('language'));
$FFSpec::patron_status       = $STSFF->new(14, $l->get('patron status'));
$FFSpec::summary             = $STSFF->new(10, $l->get('summary'));
$FFSpec::hold_items_count    = $STSFF->new(4,  $l->get('hold items count'));
$FFSpec::overdue_items_count = $STSFF->new(4,  $l->get('overdue items count'));
$FFSpec::charged_items_count = $STSFF->new(4,  $l->get('charged items count'));
$FFSpec::fine_items_count    = $STSFF->new(4,  $l->get('fine items count'));
$FFSpec::recall_items_count  = $STSFF->new(4,  $l->get('recall items count'));
$FFSpec::unavail_holds_count = $STSFF->new(4,  $l->get('unavail holds count'));
$FFSpec::sc_renewal_policy   = $STSFF->new(1,  $l->get('sc renewal policy'));
$FFSpec::no_block            = $STSFF->new(1,  $l->get('no block'));
$FFSpec::nb_due_date         = $STSFF->new(18, $l->get('nb due date'));
$FFSpec::renewal_ok          = $STSFF->new(1,  $l->get('renewal ok'));
$FFSpec::magnetic_media      = $STSFF->new(1,  $l->get('magnetic media'));
$FFSpec::desensitize         = $STSFF->new(1,  $l->get('desensitize'));
$FFSpec::resensitize         = $STSFF->new(1,  $l->get('resensitize'));
$FFSpec::return_date         = $STSFF->new(18, $l->get('return date'));
$FFSpec::alert               = $STSFF->new(1,  $l->get('alert'));
$FFSpec::status_code         = $STSFF->new(1,  $l->get('status code'));
$FFSpec::max_print_width     = $STSFF->new(3,  $l->get('max print width'));
$FFSpec::protocol_version    = $STSFF->new(4,  $l->get('protocol version'));
$FFSpec::online_status       = $STSFF->new(1,  $l->get('on-line status'));
$FFSpec::checkin_ok          = $STSFF->new(1,  $l->get('checkin ok'));
$FFSpec::checkout_ok         = $STSFF->new(1,  $l->get('checkout ok'));
$FFSpec::acs_renewal_policy  = $STSFF->new(1,  $l->get('acs renewal policy'));
$FFSpec::status_update_ok    = $STSFF->new(1,  $l->get('status update ok'));
$FFSpec::offline_ok          = $STSFF->new(1,  $l->get('offline ok'));
$FFSpec::timeout_period      = $STSFF->new(3,  $l->get('timeout period'));
$FFSpec::retries_allowed     = $STSFF->new(3,  $l->get('retries allowed'));
$FFSpec::date_time_sync      = $STSFF->new(18, $l->get('date/time sync'));

# --- Variable-Length Field Definitions -------------------------------------

package FSpec;
use strict; use warnings;

my $STSF = 'SIP2Mediator::Spec::Field'; # shorthand

$FSpec::patron_id          = $STSF->new('AA', $l->get('patron identifier'));
$FSpec::item_id            = $STSF->new('AB', $l->get('item identifier'));
$FSpec::terminal_pwd       = $STSF->new('AC', $l->get('terminal password'));
$FSpec::patron_pwd         = $STSF->new('AD', $l->get('patron password'));
$FSpec::patron_name        = $STSF->new('AE', $l->get('personal name'));
$FSpec::screen_msg         = $STSF->new('AF', $l->get('screen message'));
$FSpec::print_line         = $STSF->new('AG', $l->get('print line'));
$FSpec::due_date           = $STSF->new('AH', $l->get('due date'));
$FSpec::title_id           = $STSF->new('AJ', $l->get('title identifier'));
$FSpec::blocked_card_msg   = $STSF->new('AL', $l->get('blocked card msg'));
$FSpec::library_name       = $STSF->new('AM', $l->get('library name'));
$FSpec::terminal_location  = $STSF->new('AN', $l->get('terminal location'));
$FSpec::institution_id     = $STSF->new('AO', $l->get('institution id'));
$FSpec::current_location   = $STSF->new('AP', $l->get('current location'));
$FSpec::permanent_location = $STSF->new('AQ', $l->get('permanent location'));
$FSpec::hold_items         = $STSF->new('AS', $l->get('hold items'));
$FSpec::overdue_items      = $STSF->new('AT', $l->get('overdue items'));
$FSpec::charged_items      = $STSF->new('AU', $l->get('charged items'));
$FSpec::fine_items         = $STSF->new('AV', $l->get('fine items'));
$FSpec::sequence_number    = $STSF->new('AY', $l->get('sequence number'));
$FSpec::checksum           = $STSF->new('AZ', $l->get('checksum'));
$FSpec::home_address       = $STSF->new('BD', $l->get('home address'));
$FSpec::email              = $STSF->new('BE', $l->get('e-mail address'));
$FSpec::home_phone         = $STSF->new('BF', $l->get('home phone number'));
$FSpec::owner              = $STSF->new('BG', $l->get('owner'));
$FSpec::currency_type      = $STSF->new('BH', $l->get('currency type'));
$FSpec::cancel             = $STSF->new('BI', $l->get('cancel'));
$FSpec::transaction_id     = $STSF->new('BK', $l->get('transaction id'));
$FSpec::valid_patron       = $STSF->new('BL', $l->get('valid patron'));
$FSpec::renewed_items      = $STSF->new('BM', $l->get('renewed items'));
$FSpec::unrenewed_items    = $STSF->new('BN', $l->get('unrenewed items'));
$FSpec::fee_acknowledged   = $STSF->new('BO', $l->get('fee acknowledged'));
$FSpec::start_item         = $STSF->new('BP', $l->get('start item'));
$FSpec::end_item           = $STSF->new('BQ', $l->get('end item'));
$FSpec::queue_position     = $STSF->new('BR', $l->get('queue position'));
$FSpec::pickup_location    = $STSF->new('BS', $l->get('pickup location'));
$FSpec::fee_type           = $STSF->new('BT', $l->get('fee type'));
$FSpec::recall_items       = $STSF->new('BU', $l->get('recall items'));
$FSpec::fee_amount         = $STSF->new('BV', $l->get('fee amount'));
$FSpec::expiration_date    = $STSF->new('BW', $l->get('expiration date'));
$FSpec::supported_messages = $STSF->new('BX', $l->get('supported messages'));
$FSpec::hold_type          = $STSF->new('BY', $l->get('hold type'));
$FSpec::hold_items_limit   = $STSF->new('BZ', $l->get('hold items limit'));
$FSpec::overdue_items_limit= $STSF->new('CA', $l->get('overdue items limit'));
$FSpec::charged_items_limit= $STSF->new('CB', $l->get('charged items limit'));
$FSpec::fee_limit          = $STSF->new('CC', $l->get('fee limit'));
$FSpec::unavail_hold_items = $STSF->new('CD', $l->get('unavailable hold items'));
$FSpec::hold_queue_length  = $STSF->new('CF', $l->get('hold queue length'));
$FSpec::fee_identifier     = $STSF->new('CG', $l->get('fee identifier'));
$FSpec::item_properties    = $STSF->new('CH', $l->get('item properties'));
$FSpec::security_inhibit   = $STSF->new('CI', $l->get('security inhibit'));
$FSpec::recall_date        = $STSF->new('CJ', $l->get('recall date'));
$FSpec::media_type         = $STSF->new('CK', $l->get('media type'));
$FSpec::sort_bin           = $STSF->new('CL', $l->get('sort bin'));
$FSpec::hold_pickup_date   = $STSF->new('CM', $l->get('hold pickup date'));
$FSpec::login_uid          = $STSF->new('CN', $l->get('login user id'));
$FSpec::login_pwd          = $STSF->new('CO', $l->get('login password'));
$FSpec::location_code      = $STSF->new('CP', $l->get('location code'));
$FSpec::valid_patron_pwd   = $STSF->new('CQ', $l->get('valid patron password'));
$FSpec::patron_inet_profile= $STSF->new('PI', $l->get('patron internet profile'));
$FSpec::call_number        = $STSF->new('CS', $l->get('call number'));
$FSpec::collection_code    = $STSF->new('CR', $l->get('collection code'));
$FSpec::alert_type         = $STSF->new('CV', $l->get('alert type'));
$FSpec::hold_patron_id     = $STSF->new('CY', $l->get('hold patron id'));
$FSpec::hold_patron_name   = $STSF->new('DA', $l->get('hold patron name'));
$FSpec::destination_location = $STSF->new('CT', $l->get('destination location'));

# Envisionware Terminal Extensions
$FSpec::patron_expire      = $STSF->new('PA', $l->get('patron expire date'));
$FSpec::patron_birth_date  = $STSF->new('PB', $l->get('patron birth date'));
$FSpec::patron_class       = $STSF->new('PC', $l->get('patron class'));
$FSpec::register_login     = $STSF->new('OR', $l->get('register login'));
$FSpec::check_number       = $STSF->new('RN', $l->get('check number'));

# --- Message Definitions ---------------------------------------------------

package MSpec;
use strict; use warnings;

my $STSM = 'SIP2Mediator::Spec::Message'; # shorthand

$MSpec::sc_status = $STSM->new(
    '99', $l->get('SC Status'), [
        $FFSpec::status_code,
        $FFSpec::max_print_width,
        $FFSpec::protocol_version
    ]
);

$MSpec::asc_status = $STSM->new(
    '98', $l->get('ASC Status'), [
        $FFSpec::online_status,
        $FFSpec::checkin_ok,
        $FFSpec::checkout_ok,
        $FFSpec::acs_renewal_policy,
        $FFSpec::status_update_ok,
        $FFSpec::offline_ok,
        $FFSpec::timeout_period,
        $FFSpec::retries_allowed,
        $FFSpec::date_time_sync,
        $FFSpec::protocol_version
    ]
);

$MSpec::login = $STSM->new(
    '93', $l->get('Login Request'), [
        $FFSpec::uid_algo,
        $FFSpec::pwd_algo
    ]
);

$MSpec::login_resp = $STSM->new(
    '94', $l->get('Login Response'), [
        $FFSpec::ok
    ]
);

$MSpec::item_info = $STSM->new(
    '17', $l->get('Item Information Request'), [ 
        $FFSpec::date
    ]
);

$MSpec::item_info_resp = $STSM->new(
    '18', $l->get('Item Information Response'), [
        $FFSpec::circ_status,
        $FFSpec::security_marker,
        $FFSpec::fee_type,
        $FFSpec::date
    ]
);


$MSpec::patron_status = $STSM->new(
    '23', $l->get('Patron Status Request'), [
        $FFSpec::language,
        $FFSpec::date
    ]
);

$MSpec::patron_status_resp = $STSM->new(
    '24', $l->get('Patron Status Response'), [
        $FFSpec::patron_status,
        $FFSpec::language,
        $FFSpec::date
    ]
);

$MSpec::patron_info = $STSM->new(
    '63', $l->get('Patron Information Request'), [
        $FFSpec::language,
        $FFSpec::date,
        $FFSpec::summary
    ]
);

$MSpec::patron_info_resp = $STSM->new(
    '64', $l->get('Patron Information Response'), [
        $FFSpec::patron_status,
        $FFSpec::language,
        $FFSpec::date,
        $FFSpec::hold_items_count,
        $FFSpec::overdue_items_count,
        $FFSpec::charged_items_count,
        $FFSpec::fine_items_count,
        $FFSpec::recall_items_count,
        $FFSpec::unavail_holds_count
    ]
);

$MSpec::checkout = $STSM->new(
    '11', $l->get('Checkout Request'), [
        $FFSpec::sc_renewal_policy,
        $FFSpec::no_block,
        $FFSpec::date,
        $FFSpec::nb_due_date
    ]
);

$MSpec::checkout_resp = $STSM->new(
    '12', $l->get('Checkout Response'), [
        $FFSpec::ok,
        $FFSpec::renewal_ok,
        $FFSpec::magnetic_media,
        $FFSpec::desensitize,
        $FFSpec::date
    ]
);

$MSpec::checkin = $STSM->new(
    '09', $l->get('Checkin Request'), [
        $FFSpec::no_block,
        $FFSpec::date,
        $FFSpec::return_date
    ]
);

$MSpec::checkin_resp = $STSM->new(
    '10', $l->get('Checkin Response'), [
        $FFSpec::ok,
        $FFSpec::resensitize,
        $FFSpec::magnetic_media,
        $FFSpec::alert,
        $FFSpec::date
    ]
);
 
$MSpec::fee_paid = $STSM->new(
    '37', $l->get('Fee Paid'), [
        $FFSpec::date,
        $FFSpec::fee_type,
        $FFSpec::payment_type,
        $FFSpec::currency_type
    ]
);

$MSpec::fee_paid_resp = $STSM->new(
    '38', $l->get('Fee Paid Response'), [
        $FFSpec::payment_accepted,
        $FFSpec::date
    ]
);

1;

