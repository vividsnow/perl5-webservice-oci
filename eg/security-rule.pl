#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Open a TCP port by adding an ingress rule to a security list. Demonstrates the
# read-modify-write pattern guarded with the ETag (if-match).
#
#   perl eg/security-rule.pl --security-list OCID --port 443 [--source 0.0.0.0/0] [--profile DEFAULT]

my %o = (source => '0.0.0.0/0');
GetOptions(\%o, qw(security-list=s port=i source=s profile=s)) or die "bad options\n";
$o{'security-list'} && $o{port} or die "usage: $0 --security-list OCID --port N [--source CIDR]\n";

my $oci = WebService::OCI->new(service => 'iaas', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $path = "/20160918/securityLists/$o{'security-list'}";
my $get  = call($oci->get($path), 'get security list');
my $sl   = $get->content;
my $etag = $get->headers->{etag};

my @ingress = @{ $sl->{ingressSecurityRules} || [] };
push @ingress, {
    protocol   => '6',                 # TCP
    source     => $o{source},
    sourceType => 'CIDR_BLOCK',
    tcpOptions => { destinationPortRange => { min => $o{port}, max => $o{port} } },
};

# PUT replaces the rule sets, so send both; if-match makes it fail on a
# concurrent change rather than clobbering it
call($oci->put($path, {
    ingressSecurityRules => \@ingress,
    egressSecurityRules  => $sl->{egressSecurityRules} || [],
}, headers => { 'if-match' => $etag }), 'update security list');

print "added ingress tcp/$o{port} from $o{source} ("
    . scalar(@ingress) . " ingress rules now)\n";
