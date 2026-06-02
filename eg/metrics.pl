#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use POSIX qw(strftime);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Query the Monitoring service for metric data with an MQL expression.
# (Read endpoint: telemetry.<region>.oraclecloud.com)
#
#   perl eg/metrics.pl --compartment OCID [--namespace oci_computeagent] \
#       [--query 'CpuUtilization[1m].mean()'] [--hours 1] [--profile DEFAULT]

my %o = (namespace => 'oci_computeagent', query => 'CpuUtilization[1m].mean()', hours => 1);
GetOptions(\%o, qw(compartment=s namespace=s query=s hours=i profile=s)) or die "bad options\n";
defined $o{compartment} or die "missing --compartment\n";

my $mon = WebService::OCI->new(service => 'telemetry', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $now = time;
my $series = call($mon->post('/20180401/metrics/actions/summarizeMetricsData', {
    namespace => $o{namespace},
    query     => $o{query},
    startTime => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($now - $o{hours} * 3600)),
    endTime   => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime($now)),
}, query => { compartmentId => $o{compartment} }), 'summarize metrics')->content;

@$series or do { print "no data for: $o{query}\n"; exit 0 };
for my $s (@$series) {
    my $pts  = $s->{aggregatedDatapoints} || [];
    my $last = $pts->[-1];
    my %dim  = %{ $s->{dimensions} || {} };
    printf "%s {%s}: %d point(s), last=%s @ %s\n",
        $s->{name} // $o{namespace},
        join(',', map { "$_=$dim{$_}" } sort keys %dim),
        scalar(@$pts),
        $last ? $last->{value} : '-',
        $last ? $last->{timestamp} : '-';
}
