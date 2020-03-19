#!/usr/bin/perl
package main;
use strict; use warnings;
use SIPTunnel::Spec;
use SIPTunnel::Spec::FixedField;
use SIPTunnel::Spec::Field;
use SIPTunnel::Spec::Message;

use SIPTunnel::FixedField;
use SIPTunnel::Field;
use SIPTunnel::Message;


print $FFSpec::date . "\n";
print $FFSpec::date->label . "\n";
print $FFSpec::date->length . "\n";

print $FSpec::media_type . "\n";
print $FSpec::media_type->code . "\n";
print $FSpec::media_type->label . "\n";

print $MSpec::fee_paid . "\n";
print $MSpec::fee_paid->code . "\n";
print $MSpec::fee_paid->label . "\n";

my $sip_msg = <<SIP;
64              00020200319    093612000000000003000100000000AOkcls|AA0030114805|AECIRCULATION TESTING PROFESSIONAL|BHUSD|BV26.00|BD123 Banana Rd Somewhere, TX 12345|BEyou\@example.org|BF555-444-3333|AQBR1|BLY|PA20220316|PB19000101|PCPatrons|PIAdult|XI12345|AFhowdy|
SIP

my $msg = SIPTunnel::Message->from_sip($sip_msg);

print $msg->to_json . "\n";

print $msg->to_str;



