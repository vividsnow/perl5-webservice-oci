#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use Getopt::Long qw(:config no_auto_abbrev);
use File::Find;

$| = 1;

# Sync a local directory up to an Object Storage bucket: list the existing
# objects (following pagination), then upload any local file not already there.
#
#   perl eg/object-sync.pl --bucket NAME --dir PATH [--prefix STR] [--profile DEFAULT]

my %o = (prefix => '');
GetOptions(\%o, qw(bucket=s dir=s prefix=s profile=s)) or die "bad options\n";
$o{bucket} && defined $o{dir} or die "usage: $0 --bucket NAME --dir PATH [--prefix STR]\n";
-d $o{dir} or die "not a directory: $o{dir}\n";

my $os = WebService::OCI->new(service => 'objectstorage', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $ns = call($os->get('/n'), 'get namespace')->content;
print "namespace: $ns, bucket: $o{bucket}\n";

# existing objects, following ListObjects pagination (nextStartWith / start)
my (%have, $start);
do {
    my $res = call($os->get("/n/$ns/b/$o{bucket}/o", query => {
        limit => 1000, (defined $start ? (start => $start) : ()) }), 'list objects');
    $have{ $_->{name} } = 1 for @{ $res->content->{objects} || [] };
    $start = $res->content->{nextStartWith};
} while (defined $start);
print scalar(keys %have), " object(s) already in bucket\n";

my @files;
find(sub { push @files, $File::Find::name if -f }, $o{dir});

my ($up, $skip) = (0, 0);
for my $path (@files) {
    (my $rel = $path) =~ s{^\Q$o{dir}\E/?}{};
    my $name = $o{prefix} . $rel;
    if ($have{$name}) { $skip++; next }
    open my $fh, '<:raw', $path or die "open $path: $!\n";
    my $bytes = do { local $/; <$fh> };
    close $fh;
    # PutObject signs only (request-target) host date - not the body digest
    call($os->put("/n/$ns/b/$o{bucket}/o/$name", undef,
        body         => $bytes,
        headers      => { 'content-type' => 'application/octet-stream' },
        sign_headers => [ '(request-target)', 'host', 'date' ]), "put $name");
    print "  uploaded $name (", length($bytes), " bytes)\n";
    $up++;
}
print "uploaded $up, skipped $skip (already present)\n";
