#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Start, stop or reset a Compute instance.
#
#   perl eg/instance-action.pl --instance OCID --action START|STOP|RESET|SOFTRESET|SOFTSTOP \
#       [--wait] [--profile DEFAULT]

my %o;
GetOptions(\%o, qw(instance=s action=s wait profile=s)) or die "bad options\n";
$o{instance} && $o{action} or die "usage: $0 --instance OCID --action START|STOP|RESET|...\n";
my $action = uc $o{action};

my $oci = WebService::OCI->new(service => 'iaas', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s (opc-request-id=%s)\n",
        $what, $res->status, $res->reason // '', $msg, $res->headers->{'opc-request-id'} // '-';
}

# InstanceAction: POST .../instances/{id}?action=ACTION with an empty body
my $inst = call($oci->post("/20160918/instances/$o{instance}", undef,
    query => { action => $action }), "instance $action")->content;
print "$o{instance}: $inst->{lifecycleState}\n";

if ($o{wait}) {
    my %target = (START => 'RUNNING', RESET => 'RUNNING', SOFTRESET => 'RUNNING',
                  STOP => 'STOPPED', SOFTSTOP => 'STOPPED');
    my $want = $target{$action} or exit 0;
    my $state = $inst->{lifecycleState};
    while ($state ne $want) {
        sleep 5;
        $state = call($oci->get("/20160918/instances/$o{instance}"), 'get instance')
            ->content->{lifecycleState};
        print "  ... $state\n";
    }
}
