#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use MIME::Base64 qw(decode_base64);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Fetch a Vault secret bundle and print (or write) the decoded value. Shows
# base_url for a realm-infix host: secrets.vaults.<region>.oci.oraclecloud.com
# does not fit the simple <service>.<region>.oraclecloud.com pattern.
#
#   perl eg/secret.pl --secret OCID [--stage CURRENT] [--out FILE] [--profile DEFAULT]

my %o = (stage => 'CURRENT');
GetOptions(\%o, qw(secret=s stage=s out=s profile=s)) or die "bad options\n";
defined $o{secret} or die "missing --secret OCID\n";

my $oci = WebService::OCI->new(($o{profile} ? (profile => $o{profile}) : ()));
my $region = $oci->region or die "no region in config\n";
my $base = "https://secrets.vaults.$region.oci.oraclecloud.com";

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $bundle = call($oci->get("/20190301/secretbundles/$o{secret}",
    base_url => $base, query => { stage => $o{stage} }), 'get secret bundle')->content;

my $c = $bundle->{secretBundleContent} || {};
my $value = ($c->{contentType} // '') eq 'BASE64'
    ? decode_base64($c->{content} // '')
    : ($c->{content} // '');

print "version: ", $bundle->{versionNumber} // '-', "\n";
if ($o{out}) {
    open my $fh, '>:raw', $o{out} or die "open $o{out}: $!\n";
    print {$fh} $value;
    close $fh;
    print "wrote ", length($value), " bytes to $o{out}\n";
}
else {
    print $value, "\n";
}
