#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);

# Create a minimal public network over the API: a VCN, an internet gateway, a
# default route to it, and a public regional subnet. Prints the subnet OCID to
# feed to launch-instance.pl. Networking resources are free.
#
#   perl eg/setup-network.pl --compartment ocid1.tenancy.oc1..aaaa [--name demo]
#       [--vcn-cidr 10.0.0.0/16] [--subnet-cidr 10.0.1.0/24] [--profile DEFAULT]

my %o = (
    'vcn-cidr'    => '10.0.0.0/16',
    'subnet-cidr' => '10.0.1.0/24',
    name          => 'demo',
);
GetOptions(\%o, qw(compartment=s vcn-cidr=s subnet-cidr=s name=s profile=s))
    or die "bad options\n";
defined $o{compartment}
    or die "usage: $0 --compartment OCID [--name demo] [--vcn-cidr ...] "
         . "[--subnet-cidr ...] [--profile DEFAULT]\n";

my $oci = WebService::OCI->new(
    service => 'iaas',
    ($o{profile} ? (profile => $o{profile}) : ()),
);

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s (opc-request-id=%s)\n",
        $what, $res->status, $res->reason // '', $msg,
        $res->headers->{'opc-request-id'} // '-';
}

# 1. VCN
my $vcn = call($oci->post('/20160918/vcns', {
    compartmentId => $o{compartment},
    cidrBlocks    => [ $o{'vcn-cidr'} ],
    displayName   => "$o{name}-vcn",
}), 'create VCN')->content;
print "VCN:          $vcn->{id}\n";

# 2. internet gateway
my $ig = call($oci->post('/20160918/internetGateways', {
    compartmentId => $o{compartment},
    vcnId         => $vcn->{id},
    isEnabled     => \1,
    displayName   => "$o{name}-ig",
}), 'create internet gateway')->content;
print "internet GW:  $ig->{id}\n";

# 3. default route table: send 0.0.0.0/0 to the internet gateway
call($oci->put("/20160918/routeTables/$vcn->{defaultRouteTableId}", {
    routeRules => [ {
        destination     => '0.0.0.0/0',
        destinationType => 'CIDR_BLOCK',
        networkEntityId => $ig->{id},
    } ],
}), 'update route table');
print "route table:  $vcn->{defaultRouteTableId} (0.0.0.0/0 -> IG)\n";

# 4. public regional subnet (the VCN's default security list already allows
#    inbound SSH on tcp/22, so an instance here is reachable)
my $subnet = call($oci->post('/20160918/subnets', {
    compartmentId          => $o{compartment},
    vcnId                  => $vcn->{id},
    cidrBlock              => $o{'subnet-cidr'},
    displayName            => "$o{name}-public-subnet",
    prohibitPublicIpOnVnic => \0,
}), 'create subnet')->content;
print "subnet:       $subnet->{id}\n";

print "\nPublic subnet ready. Launch an instance with:\n";
print "  perl eg/launch-instance.pl \\\n";
print "      --compartment $o{compartment} \\\n";
print "      --subnet $subnet->{id} \\\n";
print "      --ssh-key ~/.ssh/id_rsa.pub\n";
