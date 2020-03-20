# SIP2Mediator

## Usage

PERL5LIB=lib ./bin/sip2-mediator --help

## About

SIP2Mediator is a SIP2 server which mediates SIP requests between a
SIP client and an HTTP backend, which is responsible for performing
the requested actions.


## Data Flow

SIP Client <=> SIP <=> SIP2Mediator <=> JSON <=> HTTP Server

