#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use File::Basename qw(basename);
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Upload a large file with an Object Storage multipart upload:
# CreateMultipartUpload -> UploadPart x N -> CommitMultipartUpload.
#
#   perl eg/multipart-upload.pl --bucket NAME --file PATH [--object NAME] [--part-mb 128] [--profile DEFAULT]

my %o = ('part-mb' => 128);
GetOptions(\%o, qw(bucket=s file=s object=s part-mb=i profile=s)) or die "bad options\n";
$o{bucket} && $o{file} or die "usage: $0 --bucket NAME --file PATH [--object NAME] [--part-mb N]\n";
-f $o{file} or die "not a file: $o{file}\n";
my $object   = $o{object} // basename($o{file});
my $partsize = $o{'part-mb'} * 1024 * 1024;

my $os = WebService::OCI->new(service => 'objectstorage', ($o{profile} ? (profile => $o{profile}) : ()));

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $ns = call($os->get('/n'), 'get namespace')->content;

# 1. create the upload
my $uid = call($os->post("/n/$ns/b/$o{bucket}/u", { object => $object }),
    'create multipart upload')->content->{uploadId};
print "uploadId: $uid\n";

# 2. upload parts (each signs like PutObject: (request-target) host date)
open my $fh, '<:raw', $o{file} or die "open $o{file}: $!\n";
my (@parts, $n);
while (read $fh, my $chunk, $partsize) {
    $n++;
    my $res = call($os->put("/n/$ns/b/$o{bucket}/u/$object", undef,
        query        => { uploadId => $uid, uploadPartNum => $n },
        body         => $chunk,
        sign_headers => [ '(request-target)', 'host', 'date' ]), "upload part $n");
    push @parts, { partNum => $n, etag => $res->headers->{etag} };
    print "  part $n: ", length($chunk), " bytes\n";
}
close $fh;
@parts or die "file is empty\n";

# 3. commit
call($os->post("/n/$ns/b/$o{bucket}/u/$object", { partsToCommit => \@parts },
    query => { uploadId => $uid }), 'commit multipart upload');
print "committed $object ($n part(s))\n";
