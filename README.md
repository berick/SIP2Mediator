# SIP2Mediator

## SIP2Mediator Server

### Install Prerequisites (Ubuntu)

```sh
sudo apt install build-essential libjson-xs-perl libnet-https-nb-perl libdatetime-perl
sudo cpan URL::Encode::XS JSON::Path
```

### Usage

#### Running the SIP2Mediator

```sh
PERL5LIB=lib bin/sip2-mediator --help

PERL5LIB=lib bin/sip2-mediator  \
    --sip-address 127.0.0.1     \
    --sip-port 6001             \
    --http-host 127.0.0.1       \
    --http-proto http           \
    --http-path /sip2-mediator  \
    --max-clients 120           \
    --syslog-facility LOCAL4
```

#### Running the SIP2Mediator Using Evergreen Gateway

PERL5LIB=lib bin/sip2-mediator              \
     --syslog-facility LOCAL4               \
     --session-param param                  \
     --message-param param                  \
     --http-method GET                      \
     --response-json-path "\$.payload[0]"   \
     --http-path "/gateway?service=open-ils.sip2&method=open-ils.sip2.request"

#### Graceful Shutdown

```sh
kill -s USR1 <sip2-mediator-pid>
```

### About

SIP2Mediator is a SIP2 server which relays SIP requests between
SIP clients and a JSON/HTTP backend.  The mediator is a single-cpu,
single-thread application which processes network data on a first come
first served basis via select loop.

Given the limited functionality of the mediator proper, system requirements
are minimal.  Similarly, since the mediator performs no ILS tasks directly,
it can integrate with any ILS which provides the required HTTP back-end.

### Data Flow

SIP Client <=> SIP <=> SIP2Mediator <=> JSON <=> HTTP Server <=> ILS Data <=> ILS

### SIP Messages as JSON

* Message exchanged with the HTTP back-end are encoded as JSON Objects
  with a "code", "fixed\_fields", and optionally "fields" keys.

Example SIP Login Message

```sh
9300|CNsip_username|COsip_password
```

```json
{                                                              
  "code": 93,                                                            
  "fixed_fields": ["0", "0"],                                            
  "fields": [
    {"CN": "sip_username"}, 
    {"CO": "sip_password"}
  ]               
}
```

## SIP2Mediator Client

A SIP2 client library and command line tool are included for testing.

```sh
PERL5LIB=lib bin/sip2-client    \
   --sip-address 127.0.0.1      \
   --sip-port 6001              \
   --sip-username siplogin      \ 
   --sip-password sippassword   \
   --institution example        \ 
   --item-barcode 123456789     \
   --patron-barcode 987654321   \
   --patron-password demo123    \
   --message sc-status          \
   --message item-information   \
   --message patron-information \
   --message patron-status
```

## SIP2Mediator and Evergreen ILS

### Project Goals

* Decouple ILS implementation from SIP server.
* Decouple SIP accounts from ILS accounts
* Back-end SIP API which survives front-end changes.
* Reduce system requirements for SIP servers
* Support load distrubution across an Evergreen cluster
* Support graceful-ish SIP server detachment
* Move SIP configuration into the Evergreen database
* Allow for configuration changes (e.g. adding SIP accounts) without 
  having to restart the SIP server.
* Decouple institution IDs from configuration settings.
* Reduce SIP message layer abstraction to ease customization.
* Support persistent and transient SIP sessions
* BONUS: In scenarios where sip2-mediator may be run alongside SIP
  clients, SIP traffic to/from EG traffic may be encrypted by HTTPS.
* BONUS: SIP actions may be performed via direct HTTPS, bypassing 
  wire-level SIP altogether.
* BONUS: Testing SIP changes via srfsh
```sh
srfsh# request open-ils.sip2 open-ils.sip2.request "randomkey", {"code":"93","fields":[{"CN":"sipuser"}, {"CO":"sippass"}]}
```

### Current Evergreen Working Branch

https://bugs.launchpad.net/evergreen/+bug/1901930


