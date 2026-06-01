#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;

# List Compute instances in a compartment, following pagination.
# The root compartment's OCID is your tenancy OCID.
#
#   perl eg/list-instances.pl <compartment-ocid> [profile]

my ($compartment, $profile) = @ARGV;
$compartment or die "usage: $0 <compartment-ocid> [profile]\n";

my $oci = WebService::OCI->new(
    service => 'iaas',
    ($profile ? (profile => $profile) : ()),
);

my (@all, $page);
do {
    my $res = $oci->get('/20160918/instances', query => {
        compartmentId => $compartment,
        limit         => 100,
        (defined $page ? (page => $page) : ()),
    });
    die "error: ", $res->status, ' ', ($res->reason // ''), "\n", ($res->raw // ''), "\n"
        unless $res->is_success;
    push @all, @{ $res->content };
    $page = $res->headers->{'opc-next-page'};
} while (defined $page);

printf "%-12s  %-26s  %s\n", 'STATE', 'NAME', 'OCID';
for my $i (@all) {
    printf "%-12s  %-26s  %s\n",
        $i->{lifecycleState} // '?', $i->{displayName} // '', $i->{id} // '';
}
print scalar(@all), " instance(s)\n";
