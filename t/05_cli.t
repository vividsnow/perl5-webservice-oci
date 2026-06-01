use strict;
use warnings;
use Test::More;
use FindBin;
use File::Temp qw(tempfile);
use WebService::OCI::Signer;

my $script = "$FindBin::Bin/../bin/oci-rest";
my $key    = "$FindBin::Bin/testkey.pem";
my @run    = ($^X, '-I', "$FindBin::Bin/../lib", $script);

ok -e $script, 'bin/oci-rest exists';

# --version
my $ver = qx{@run --version 2>&1};
is $?, 0, '--version exits 0';
like $ver, qr/oci-rest \d/, '--version prints version';

# --help
my $help = qx{@run --help 2>&1};
is $? >> 8, 0, '--help exits 0';
like $help, qr/Usage:/, '--help prints usage';

# unknown command -> usage error, exit 1
qx{@run bogus /x 2>/dev/null};
is $? >> 8, 1, 'unknown command exits 1';

# fingerprint matches the library (and thus openssl)
my $want = WebService::OCI::Signer->new(key_file => $key)->key_fingerprint;
chomp(my $got = qx{@run fingerprint $key 2>&1});
is $got, $want, 'fingerprint subcommand matches Signer';

# end-to-end signing path, offline: point at a dead port and inspect --debug.
# Connection fails (HTTP::Tiny status 599) so exit is 2, but signing ran.
my ($fh, $cfg) = tempfile(UNLINK => 1);
print {$fh} <<"INI";
[DEFAULT]
user=ocid1.user.oc1..u
fingerprint=aa:bb:cc:dd
tenancy=ocid1.tenancy.oc1..t
region=us-ashburn-1
key_file=$key
INI
close $fh;

my $dbg = qx{@run --config $cfg --endpoint http://127.0.0.1:1 --timeout 2 --debug get /20160918/instances -p compartmentId=c 2>&1 1>/dev/null};
is $? >> 8, 2, 'failed HTTP request exits 2';
like $dbg, qr/signing string/,                       'debug shows signing string';
like $dbg, qr/\Q(request-target): get /,             'debug shows request-target';
like $dbg, qr/authorization: Signature version="1"/, 'debug shows authorization header';

# a valueless --param produces a bare key (no '='), distinct from --param k=
my $bare = qx{@run --config $cfg --endpoint http://127.0.0.1:1 --timeout 2 --debug get /x -p flag -p kv=1 2>&1 1>/dev/null};
like $bare, qr{\Q(request-target): get /x?flag&kv=1\E},
   'valueless --param emits a bare key, --param k=v emits key=value';

# configure: non-interactive smoke - pipe answers, write a profile, mode 0600.
# Fork so the child's stdout/stderr go to /dev/null and never pollute TAP.
SKIP: {
    my ($cfh, $cfg2) = tempfile(UNLINK => 1);
    close $cfh;
    my $fp = WebService::OCI::Signer->new(key_file => $key)->key_fingerprint;
    my $answers = join("\n",
        'ocid1.user.oc1..u',     # user OCID
        'ocid1.tenancy.oc1..t',  # tenancy OCID
        'eu-frankfurt-1',        # region
        $key,                    # key_file (readable -> fingerprint derived)
        '',                      # accept the derived fingerprint
        'y',                     # confirm the append
    ) . "\n";

    my $pid = open(my $pipe, '|-');
    skip 'cannot fork', 3 unless defined $pid;
    if (!$pid) {
        open STDOUT, '>', '/dev/null';
        open STDERR, '>', '/dev/null';
        exec @run, '--config', $cfg2, '--profile', 'TESTCONF', 'configure';
        exit 127;
    }
    print {$pipe} $answers;
    close $pipe;

    my $written = do { open my $f, '<', $cfg2 or die "open $cfg2: $!"; local $/; <$f> };
    like $written, qr/^\[TESTCONF\]/m,         'configure wrote the named profile';
    like $written, qr/\Qfingerprint=$fp\E/,    'configure derived the fingerprint from the key';
    is +(stat $cfg2)[2] & 07777, 0600,         'configure set mode 0600';
}

# --body is read and signed (offline: dead port, inspect --debug)
my $bodydbg = qx{@run --config $cfg --endpoint http://127.0.0.1:1 --timeout 2 --debug post /x --body '{"k":1}' 2>&1 1>/dev/null};
like $bodydbg, qr{\Q(request-target): post /x\E}, '--body sends a POST';
like $bodydbg, qr/x-content-sha256:/,             '--body adds x-content-sha256';
like $bodydbg, qr/content-length: 7\b/,           '--body sets content-length';

# $OCI_CLI_PROFILE selects the profile when --profile is absent
my ($pfh, $pcfg) = tempfile(UNLINK => 1);
print {$pfh} <<"INI";
[DEFAULT]
user=u
fingerprint=aa:bb
tenancy=ocid1.tenancy.oc1..DEFAULTONE
region=us-ashburn-1
key_file=$key

[PROD]
user=u
fingerprint=aa:bb
tenancy=ocid1.tenancy.oc1..PRODTWO
region=us-ashburn-1
key_file=$key
INI
close $pfh;
my $env_prof = qx{OCI_CLI_PROFILE=PROD @run --config $pcfg --endpoint http://127.0.0.1:1 --timeout 2 --debug get /x 2>&1 1>/dev/null};
like $env_prof, qr{keyId="ocid1\.tenancy\.oc1\.\.PRODTWO/}, 'OCI_CLI_PROFILE picks the PROD profile';
my $env_def = qx{@run --config $pcfg --endpoint http://127.0.0.1:1 --timeout 2 --debug get /x 2>&1 1>/dev/null};
like $env_def, qr{keyId="ocid1\.tenancy\.oc1\.\.DEFAULTONE/}, 'without the env var, DEFAULT is used';

# --query / --output raw against a one-shot local HTTP server
SKIP: {
    eval { require IO::Socket::INET; 1 } or skip 'IO::Socket::INET unavailable', 2;
    chomp(my $q = http_roundtrip('{"items":[{"id":"XYZ"}]}', 'application/json',
        'get', '/x', '--query', 'items.0.id') // '');
    is $q, 'XYZ', '--query extracts a nested value from the JSON response';
    my $raw = http_roundtrip('plain-bytes', 'text/plain', 'get', '/x', '--output', 'raw') // '';
    is $raw, 'plain-bytes', '--output raw writes the response body verbatim';
}

done_testing;

# one-shot HTTP/1.1 server on an ephemeral port; runs oci-rest against it
sub http_roundtrip {
    my ($body, $ct, @args) = @_;
    my $srv = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1', LocalPort => 0, Listen => 1, ReuseAddr => 1) or return;
    my $port = $srv->sockport;
    my $pid  = fork;
    return unless defined $pid;
    if (!$pid) {
        alarm 15;
        if (my $c = $srv->accept) {
            local $/ = "\r\n";
            while (my $l = <$c>) { last if $l eq "\r\n" }   # consume request headers
            print {$c} "HTTP/1.1 200 OK\r\nContent-Type: $ct\r\n"
                . 'Content-Length: ' . length($body) . "\r\nConnection: close\r\n\r\n" . $body;
            close $c;
        }
        exit 0;
    }
    close $srv;
    my $out = qx{@run --config $cfg --endpoint http://127.0.0.1:$port --timeout 5 @args 2>/dev/null};
    waitpid $pid, 0;
    return $out;
}
