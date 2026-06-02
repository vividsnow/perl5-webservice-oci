#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;

$| = 1;   # unbuffered, so progress shows up live in a redirected/background log

# Launch a Compute instance end to end: pick an availability domain and image,
# launch, wait for RUNNING, then print the public IP and an ssh command.
#
# You need a compartment, an existing subnet (in a VCN with an internet gateway
# and a route to it, in a public subnet), and your SSH public key.
#
#   perl eg/launch-instance.pl \
#       --compartment ocid1.compartment.oc1..aaaa \
#       --subnet      ocid1.subnet.oc1.phx.aaaa \
#       --ssh-key     ~/.ssh/id_rsa.pub \
#       [--shape VM.Standard.E2.1.Micro] [--name demo] \
#       [--os "Oracle Linux"] [--profile DEFAULT] [--retry 300]
#
# --retry SECONDS keeps re-sweeping the ADs on transient failures: out of host
# capacity (common for free A1.Flex) and 429/5xx rate-limit/server errors.
# Ctrl-C to stop.

use Getopt::Long qw(:config no_auto_abbrev);
my %o = (
    shape => 'VM.Standard.E2.1.Micro',   # Always Free eligible (AMD x86)
    name  => 'demo-instance',
    os    => 'Oracle Linux',
    retry => 0,
);
GetOptions(\%o, qw(
    compartment=s subnet=s ssh-key=s shape=s name=s os=s profile=s retry=i
)) or die "bad options\n";
for my $req (qw(compartment subnet ssh-key)) {
    defined $o{$req} or die "missing --$req (see the header of this script)\n";
}

# read the SSH public key (a single line)
open my $kfh, '<', $o{'ssh-key'} or die "open $o{'ssh-key'}: $!\n";
my $ssh_key = <$kfh>;
close $kfh;
chomp $ssh_key;

my $oci = WebService::OCI->new(
    service => 'iaas',
    ($o{profile} ? (profile => $o{profile}) : ()),
);

# die with a useful message on any non-2xx
sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s (opc-request-id=%s)\n",
        $what, $res->status, $res->reason // '', $msg,
        $res->headers->{'opc-request-id'} // '-';
}

# 1. availability domains (Identity service); we try each for capacity
my $ads = call($oci->get('/20160918/availabilityDomains',
    service => 'identity', query => { compartmentId => $o{compartment} }),
    'list availability domains')->content;
@$ads or die "no availability domains in this compartment\n";
my @ad_names = map { $_->{name} } @$ads;
print "availability domains: ", join(', ', @ad_names), "\n";

# 2. newest image matching the OS and shape
my $images = call($oci->get('/20160918/images', query => {
    compartmentId   => $o{compartment},
    operatingSystem => $o{os},
    shape           => $o{shape},
    sortBy          => 'TIMECREATED',
    sortOrder       => 'DESC',
    limit           => 1,
}), 'list images')->content;
@$images or die "no $o{os} image found for shape $o{shape}\n";
my $image_id = $images->[0]{id};
print "image: $images->[0]{displayName}\n";

# 3. launch, trying each availability domain until one has capacity
my %body = (
    compartmentId     => $o{compartment},
    shape             => $o{shape},
    displayName       => $o{name},
    sourceDetails     => { sourceType => 'image', imageId => $image_id },
    createVnicDetails => { subnetId => $o{subnet}, assignPublicIp => \1 },
    metadata          => { ssh_authorized_keys => $ssh_key },
);
# flex shapes (e.g. VM.Standard.A1.Flex) require a shapeConfig
$body{shapeConfig} = { ocpus => 1, memoryInGBs => 6 } if $o{shape} =~ /Flex/i;

my $inst;
my $attempt = 0;
while (!$inst) {
    $attempt++;
    for my $ad (@ad_names) {
        $body{availabilityDomain} = $ad;
        my $res = $oci->post('/20160918/instances', \%body);
        if ($res->is_success) { $inst = $res->content; print "launching in $ad\n"; last }
        my $b   = $res->content;
        my $msg = ref $b eq 'HASH' ? ($b->{message} // '') : ($b // '');
        # transient: out-of-host-capacity (500) and rate-limit/server errors
        # (429 and other 5xx). Keep sweeping; a real client error (4xx) is fatal.
        if ($res->status == 429 || $res->status >= 500) {
            printf "  %s: %s %s\n", $ad, $res->status, $msg || $res->reason || '';
            next;
        }
        die sprintf "launch failed in %s: %s %s - %s (opc-request-id=%s)\n",
            $ad, $res->status, $res->reason // '', $msg,
            $res->headers->{'opc-request-id'} // '-';
    }
    last if $inst || !$o{retry};
    print "attempt $attempt: no instance yet; retrying in $o{retry}s (Ctrl-C to stop)...\n";
    sleep $o{retry};
}
$inst or die "could not launch in any AD (@ad_names): no capacity or rate-limited.\n"
    . "Free A1.Flex capacity is scarce. Re-run with '--retry 300' to keep trying,\n"
    . "or use a paid shape.\n";
my $id = $inst->{id};
print "launched $id ($inst->{lifecycleState})\n";

# 4. wait for RUNNING
my $state = $inst->{lifecycleState};
while ($state ne 'RUNNING') {
    die "instance entered $state\n" if $state =~ /TERMINat|FAIL/i;
    sleep 5;
    $state = call($oci->get("/20160918/instances/$id"), 'get instance')
        ->content->{lifecycleState};
    print "  ... $state\n";
}

# 5. find the primary VNIC and its public IP
my $att;
for (1 .. 12) {
    my $list = call($oci->get('/20160918/vnicAttachments', query => {
        compartmentId => $o{compartment}, instanceId => $id }),
        'list vnic attachments')->content;
    ($att) = grep { ($_->{lifecycleState} // '') eq 'ATTACHED' && $_->{vnicId} } @$list;
    last if $att;
    sleep 5;
}
$att or die "no attached VNIC yet; check the Console\n";

my $vnic = call($oci->get("/20160918/vnics/$att->{vnicId}"), 'get vnic')->content;
print "private IP: ", $vnic->{privateIp} // '-', "\n";
print "public  IP: ", $vnic->{publicIp}  // '(none)', "\n";
print "\nssh opc\@$vnic->{publicIp}\n" if $vnic->{publicIp};
