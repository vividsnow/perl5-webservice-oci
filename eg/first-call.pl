#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;

# Hello world: print your Object Storage namespace.
# Uses the DEFAULT profile from ~/.oci/config. See WebService::OCI::Guide.
#
#   perl eg/first-call.pl

my $oci = WebService::OCI->new(service => 'objectstorage');
my $res = $oci->get('/n');

die "request failed: ", $res->status, ' ', ($res->reason // ''), "\n",
    ($res->raw // ''), "\n"
    unless $res->is_success;

print "namespace: ", $res->content, "\n";
