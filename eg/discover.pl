#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Discover what you can launch in a region: availability domains, the shapes
# offered in each AD, and recent images. Useful when a shape/image combo is
# rejected or out of capacity.
#
#   perl eg/discover.pl --compartment OCID [--shape NAME] [--os "Oracle Linux"] [--profile DEFAULT]

my %o = (os => 'Oracle Linux');
GetOptions(\%o, qw(compartment=s shape=s os=s profile=s)) or die "bad options\n";
defined $o{compartment} or die "missing --compartment\n";

my $oci = WebService::OCI->new(service => 'iaas', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $ads = call($oci->get('/20160918/availabilityDomains',
    service => 'identity', query => { compartmentId => $o{compartment} }),
    'list availability domains')->content;
my @ad = map { $_->{name} } @$ads;
print "availability domains: ", join(', ', @ad), "\n\n";

print "shapes offered per AD:\n";
for my $ad (@ad) {
    my $sh = call($oci->get('/20160918/shapes', query => {
        compartmentId => $o{compartment}, availabilityDomain => $ad }),
        'list shapes')->content;
    my %seen;
    my @names = grep { !$seen{$_}++ } map { $_->{shape} } @$sh;
    print "  $ad: ", (@names ? join(', ', @names) : '(none)'), "\n";
}

my %iq = (
    compartmentId   => $o{compartment},
    operatingSystem => $o{os},
    sortBy          => 'TIMECREATED',
    sortOrder       => 'DESC',
    limit           => 5,
);
$iq{shape} = $o{shape} if $o{shape};
my $imgs = call($oci->get('/20160918/images', query => \%iq), 'list images')->content;
print "\nrecent $o{os} images", ($o{shape} ? " for $o{shape}" : ''), ":\n";
printf "  %-46s %s\n", $_->{displayName}, $_->{id} for @$imgs;
