#!/usr/bin/perl
use strict;
use warnings;
use SIP2Mediator::Client;
use SIP2Mediator::Message;
use SIP2Mediator::Spec;
use SIP2Mediator::Field;
use SIP2Mediator::FixedField;

my $sip_username = 'admin';
my $sip_password = 'demo123';
my $institution = 'gapines';
my $patron_barcode = '99999373998';

my $client = SIP2Mediator::Client->new({
    syslog_facility => 'LOCAL0',
    sip_address => 'localhost',
    sip_port => 6001
});

die "Client unable to connect\n" unless $client->connect;

my $login_hash = {
    code => '93',
    fixed_fields => ['0', '0'],
    fields => [{CN => $sip_username}, {CO => $sip_password}]
};

my $login = SIP2Mediator::Message->from_hash($login_hash);

print "SENDING:\n" . $login->to_str . "\n";

$client->send($login);

my $resp = $client->recv;

print "RECEIVED:\n" . $resp->to_str . "\n";

my $patron_status_hash = {
    code => '23',
    fixed_fields => ['000', SIP2Mediator::Spec->sip_date],
    fields => [{AO => $institution}, {AA => $patron_barcode}]
};

my $patron_status = SIP2Mediator::Message->from_hash($patron_status_hash);

print "SENDING:\n" . $patron_status->to_str . "\n";

$client->send($patron_status);

$resp = $client->recv;

print "RECEIVED:\n" . $resp->to_str . "\n";

__DATA__

# Programatic version of login

my $login_spec = SIP2Mediator::Spec::Message->find_by_code('93');

my $login = SIP2Mediator::Message->new(
    spec => $login_spec,
    fixed_fields => [
        SIP2Mediator::FixedField->new($login_spec->fixed_fields->[0], '0'),
        SIP2Mediator::FixedField->new($login_spec->fixed_fields->[1], '0')
    ]
);

$login->add_field(
    SIP2Mediator::Spec::Field->find_by_code('CN'), $sip_username);

$login->add_field(
    SIP2Mediator::Spec::Field->find_by_code('CO'), $sip_password);

