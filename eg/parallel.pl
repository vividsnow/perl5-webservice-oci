#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use File::Temp qw(tempdir);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Fan out concurrent requests with fork. A synchronous client is not safe to
# share across in-flight requests (its keep-alive socket and signer are
# stateful), so each worker builds its OWN client. Here we fetch every
# instance's state and public IP in a compartment, in parallel.
#
#   perl eg/parallel.pl --compartment OCID [--concurrency 8] [--profile DEFAULT]

my %o = (concurrency => 8);
GetOptions(\%o, qw(compartment=s concurrency=i profile=s)) or die "bad options\n";
defined $o{compartment} or die "missing --compartment\n";

my @client_args = (service => 'iaas', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

# 1. list instances (parent, one client)
my $parent = WebService::OCI->new(@client_args);
my $insts = call($parent->get('/20160918/instances',
    query => { compartmentId => $o{compartment}, limit => 100 }), 'list instances')->content;
@$insts or do { print "no instances\n"; exit 0 };
print scalar(@$insts), " instance(s); up to $o{concurrency} workers\n";

# 2. one forked worker per instance (each with its own client), result to a file
my $dir = tempdir(CLEANUP => 1);
my %running;
for my $i (0 .. $#$insts) {
    while (keys %running >= $o{concurrency}) { delete $running{ +wait } }
    my $pid = fork // die "fork: $!\n";
    if (!$pid) {
        my $inst = $insts->[$i];
        my $oci  = WebService::OCI->new(@client_args);   # own client per worker
        my $ip   = '-';
        my $atts = $oci->get('/20160918/vnicAttachments',
            query => { compartmentId => $o{compartment}, instanceId => $inst->{id} });
        if ($atts->is_success and my ($a) = grep { $_->{vnicId} } @{ $atts->content }) {
            my $v = $oci->get("/20160918/vnics/$a->{vnicId}");
            $ip = $v->content->{publicIp} // '-' if $v->is_success;
        }
        open my $w, '>', "$dir/$i" or exit 1;
        print {$w} join "\t", $inst->{lifecycleState} // '?', $inst->{displayName} // '', $ip;
        close $w;
        exit 0;
    }
    $running{$pid} = 1;
}
1 while wait != -1;   # reap the rest

# 3. collect + print
printf "%-12s  %-24s  %s\n", 'STATE', 'NAME', 'PUBLIC IP';
for my $i (0 .. $#$insts) {
    open my $r, '<', "$dir/$i" or next;
    chomp(my $line = <$r>);
    close $r;
    printf "%-12s  %-24s  %s\n", split /\t/, $line, 3;
}
