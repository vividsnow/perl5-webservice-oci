#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use WebService::OCI::Config;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# List compartments under a parent (default: the whole tenancy subtree),
# following pagination. Handy for finding compartment OCIDs.
#
#   perl eg/list-compartments.pl [--compartment OCID] [--profile DEFAULT]

my %o;
GetOptions(\%o, qw(compartment=s profile=s)) or die "bad options\n";

my $compartment = $o{compartment};
unless ($compartment) {
    my $home = defined $ENV{HOME} ? $ENV{HOME} : $ENV{USERPROFILE};
    defined $home or die "give --compartment, or set HOME for the config\n";
    my $file = defined $ENV{OCI_CONFIG_FILE} ? $ENV{OCI_CONFIG_FILE} : "$home/.oci/config";
    my %cfg = WebService::OCI::Config->load($file, $o{profile});
    $compartment = $cfg{tenancy};   # the tenancy is the root compartment
}

my $oci = WebService::OCI->new(service => 'identity', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my (@all, $page);
do {
    my $res = call($oci->get('/20160918/compartments', query => {
        compartmentId          => $compartment,
        compartmentIdInSubtree => 'true',
        accessLevel            => 'ANY',
        limit                  => 100,
        (defined $page ? (page => $page) : ()),
    }), 'list compartments');
    push @all, @{ $res->content };
    $page = $res->headers->{'opc-next-page'};
} while (defined $page);

printf "%-10s  %-30s  %s\n", 'STATE', 'NAME', 'OCID';
for my $c (@all) {
    printf "%-10s  %-30s  %s\n", $c->{lifecycleState} // '?', $c->{name} // '', $c->{id} // '';
}
print scalar(@all), " compartment(s)\n";
