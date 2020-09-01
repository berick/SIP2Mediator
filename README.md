# SIP2Mediator

## SIP2Mediator Server

### Install Prerequisites (Ubuntu)

```sh
sudo apt install build-essential libjson-xs-perl libnet-https-nb-perl
sudo cpan URL::Encode::XS
```

### Usage

```sh
PERL5LIB=lib bin/sip2-mediator --help
```

### About

SIP2Mediator is a SIP2 server which mediates SIP requests between
SIP clients and a JSON/HTTP backend.  The mediator is a single-cpu,
single-thread application which processes network data on a first come
first served basis via select loop.

Given the limited functionality of the mediator proper, system requirements
are minimal.  Similarly, since the mediator performs no ILS tasks directly,
it can integrate with any ILS which provides the required HTTP back-end.

### Data Flow

SIP Client <=> SIP <=> SIP2Mediator <=> JSON <=> HTTP Server

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

* Reduce system requirements for SIP servers
* Support load distrubution across an Evergreen cluster
* Support graceful SIP server detachment
* Support SIP configuration reloading
* Decouple SIP accounts from ILS accounts
* Move SIP configuration into the Evergreen database
* Reduce SIP message layer abstraction to ease modification.
* BONUS: In scenarios where sip2-mediator may be run alongside SIP
  clients, SIP traffic to/from EG traffic may be encrypted by HTTPS.

### Current Evergreen Working Branch

https://github.com/berick/Evergreen/tree/sip2-mediator



