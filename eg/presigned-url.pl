#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use POSIX qw(strftime);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Create an Object Storage pre-authenticated request (PAR) and print the
# shareable URL - it lets anyone read the object with no OCI credentials.
#
#   perl eg/presigned-url.pl --bucket NAME --object KEY [--days 7] [--name LABEL] [--profile DEFAULT]

my %o = (days => 7, name => 'demo-par');
GetOptions(\%o, qw(bucket=s object=s days=i name=s profile=s)) or die "bad options\n";
$o{bucket} && defined $o{object} or die "usage: $0 --bucket NAME --object KEY [--days N]\n";

my $os = WebService::OCI->new(service => 'objectstorage', ($o{profile} ? (profile => $o{profile}) : ()));
my $region = $os->region or die "no region in config\n";

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $ns      = call($os->get('/n'), 'get namespace')->content;
my $expires = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime(time + $o{days} * 86400));

my $par = call($os->post("/n/$ns/b/$o{bucket}/p/", {
    name        => $o{name},
    accessType  => 'ObjectRead',
    objectName  => $o{object},
    timeExpires => $expires,
}), 'create PAR')->content;

# accessUri is a relative path; prepend the Object Storage endpoint
print "expires: $expires\n";
print "url: https://objectstorage.$region.oraclecloud.com$par->{accessUri}\n";
