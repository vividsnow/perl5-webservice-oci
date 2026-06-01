#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;

# Object Storage tour: namespace, list buckets, and (optionally) upload a file
# then download it back. Demonstrates the PutObject signing exception.
#
#   perl eg/objectstorage.pl <compartment-ocid> <bucket> [file-to-upload]

my ($compartment, $bucket, $file) = @ARGV;
$compartment && $bucket or die "usage: $0 <compartment-ocid> <bucket> [file]\n";

my $os = WebService::OCI->new(service => 'objectstorage');

my $ns = $os->get('/n')->content or die "could not read namespace\n";
print "namespace: $ns\n";

my $list = $os->get("/n/$ns/b", query => { compartmentId => $compartment });
die "list buckets: ", ($list->reason // ''), "\n" unless $list->is_success;
print "buckets: ", join(', ', map { $_->{name} } @{ $list->content }), "\n";

exit 0 unless defined $file;

open my $fh, '<:raw', $file or die "open $file: $!\n";
my $bytes = do { local $/; <$fh> };
close $fh;
(my $name = $file) =~ s{.*/}{};

# PutObject signs only (request-target), host and date - not the body digest.
my $put = $os->put("/n/$ns/b/$bucket/o/$name", undef,
    body         => $bytes,
    headers      => { 'content-type' => 'application/octet-stream' },
    sign_headers => [ '(request-target)', 'host', 'date' ],
);
die "upload: ", $put->status, ' ', ($put->reason // ''), "\n" unless $put->is_success;
print "uploaded $name (", length($bytes), " bytes)\n";

my $get = $os->get("/n/$ns/b/$bucket/o/$name");
die "download: ", ($get->reason // ''), "\n" unless $get->is_success;
print "downloaded ", length($get->raw), " bytes back\n";
