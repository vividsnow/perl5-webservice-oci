#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Download every object from a bucket into a local directory (the mirror of
# object-sync.pl). Follows ListObjects pagination.
#
#   perl eg/object-pull.pl --bucket NAME --dir PATH [--prefix STR] [--profile DEFAULT]

my %o;
GetOptions(\%o, qw(bucket=s dir=s prefix=s profile=s)) or die "bad options\n";
$o{bucket} && defined $o{dir} or die "usage: $0 --bucket NAME --dir PATH [--prefix STR]\n";

my $os = WebService::OCI->new(service => 'objectstorage', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $ns = call($os->get('/n'), 'get namespace')->content;

my (@names, $start);
do {
    my $res = call($os->get("/n/$ns/b/$o{bucket}/o", query => {
        limit => 1000,
        (defined $o{prefix} ? (prefix => $o{prefix}) : ()),
        (defined $start     ? (start  => $start)     : ()),
    }), 'list objects');
    push @names, map { $_->{name} } @{ $res->content->{objects} || [] };
    $start = $res->content->{nextStartWith};
} while (defined $start);
print scalar(@names), " object(s) to download\n";

for my $name (@names) {
    my $res  = call($os->get("/n/$ns/b/$o{bucket}/o/$name"), "get $name");
    my $path = "$o{dir}/$name";
    make_path(dirname($path));
    open my $fh, '>:raw', $path or die "open $path: $!\n";
    print {$fh} $res->raw // '';
    close $fh;
    print "  $name (", length($res->raw // ''), " bytes)\n";
}
