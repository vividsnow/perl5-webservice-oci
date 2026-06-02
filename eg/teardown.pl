#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Tear down demo resources created by launch-instance.pl / setup-network.pl:
# terminate an instance and/or delete a VCN (its subnets and internet gateways
# first, then the VCN). Networking is free, but a running instance can bill -
# clean up when done.
#
#   perl eg/teardown.pl --compartment OCID [--instance OCID] [--vcn OCID] [--profile DEFAULT]

my %o;
GetOptions(\%o, qw(compartment=s instance=s vcn=s profile=s)) or die "bad options\n";
defined $o{compartment} or die "missing --compartment\n";
$o{instance} || $o{vcn} or die "give --instance and/or --vcn to delete\n";

my $oci = WebService::OCI->new(
    service => 'iaas',
    ($o{profile} ? (profile => $o{profile}) : ()),
);

# treat 404 as success - the resource is already gone
sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success || $res->status == 404;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s (opc-request-id=%s)\n",
        $what, $res->status, $res->reason // '', $msg,
        $res->headers->{'opc-request-id'} // '-';
}

# poll a resource until it is gone (404) or TERMINATED
sub wait_gone {
    my ($path, $what) = @_;
    for (1 .. 60) {
        my $res = $oci->get($path);
        return if $res->status == 404;
        return if $res->is_success && ($res->content->{lifecycleState} // '') eq 'TERMINATED';
        sleep 4;
    }
    warn "  timed out waiting for $what to delete\n";
}

if ($o{instance}) {
    print "terminating instance $o{instance}\n";
    call($oci->delete("/20160918/instances/$o{instance}",
        query => { preserveBootVolume => 'false' }), 'terminate instance');
    wait_gone("/20160918/instances/$o{instance}", 'instance');
    print "  instance terminated\n";
}

if ($o{vcn}) {
    # subnets first: a subnet cannot be deleted while a VNIC still uses it
    my $subnets = call($oci->get('/20160918/subnets',
        query => { compartmentId => $o{compartment}, vcnId => $o{vcn} }),
        'list subnets')->content;
    for my $sn (@$subnets) {
        print "deleting subnet $sn->{id}\n";
        call($oci->delete("/20160918/subnets/$sn->{id}"), 'delete subnet');
        wait_gone("/20160918/subnets/$sn->{id}", 'subnet');
    }

    my $igs = call($oci->get('/20160918/internetGateways',
        query => { compartmentId => $o{compartment}, vcnId => $o{vcn} }),
        'list internet gateways')->content;
    for my $ig (@$igs) {
        print "deleting internet gateway $ig->{id}\n";
        call($oci->delete("/20160918/internetGateways/$ig->{id}"), 'delete internet gateway');
        wait_gone("/20160918/internetGateways/$ig->{id}", 'internet gateway');
    }

    # the VCN's default route table, security list and DHCP options go with it
    print "deleting VCN $o{vcn}\n";
    call($oci->delete("/20160918/vcns/$o{vcn}"), 'delete VCN');
    wait_gone("/20160918/vcns/$o{vcn}", 'VCN');
}

print "done.\n";
