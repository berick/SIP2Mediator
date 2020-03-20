# SIP2Mediator

## Usage

PERL5LIB=lib ./bin/sip2-mediator --help

## About

SIP2Mediator is a SIP2 server which mediates SIP requests between SIP
clients and an HTTP backend.  The mediator is a single-cpu, single-thread
application which processes network data on a first come first served basis
via select loop.

Given the limited functionality of the mediator proper, RAM requirements
are minimal.

## Data Flow

SIP Client <=> SIP <=> SIP2Mediator <=> JSON <=> HTTP Server



