#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use JSON::PP ();

# A tiny generic caller - what oci-rest does, in a dozen lines.
#
#   perl eg/raw-request.pl GET objectstorage /n
#   perl eg/raw-request.pl GET iaas /20160918/instances compartmentId=ocid1..c

my ($method, $service, $path, @params) = @ARGV;
$method && $service && $path
    or die "usage: $0 METHOD SERVICE PATH [query-key=value ...]\n";

my @query;
for (@params) {
    my ($k, $v) = split /=/, $_, 2;   # bare key (no '=') keeps an undef value
    push @query, $k, $v;
}

my $oci = WebService::OCI->new(service => $service);
my $res = $oci->request(
    method => uc $method,
    path   => $path,
    (@query ? (query => \@query) : ()),
);

warn $res->status, ' ', ($res->reason // ''), "\n";

my $body = $res->content;
print ref $body
    ? JSON::PP->new->utf8->pretty->canonical->encode($body)
    : (defined $body ? "$body\n" : '');

exit($res->is_success ? 0 : 2);   # 2 = HTTP error, matching oci-rest
