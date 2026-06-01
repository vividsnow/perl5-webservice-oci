use strict;
use warnings;
use Test::More;
use FindBin;
use MIME::Base64 qw(encode_base64 decode_base64);
use Digest::SHA qw(sha256);
use Crypt::PK::RSA;
use WebService::OCI::Signer;

my $keyfile = "$FindBin::Bin/testkey.pem";
my $pk = Crypt::PK::RSA->new($keyfile);

# locale-independent IMF-fixdate: epoch 0 is a known fixed point
is WebService::OCI::Signer::_imf_date(0),
   'Thu, 01 Jan 1970 00:00:00 GMT', 'IMF date at epoch 0';

my $signer = WebService::OCI::Signer->new(
    tenancy     => 'ocid1.tenancy.oc1..aaaa',
    user        => 'ocid1.user.oc1..bbbb',
    fingerprint => 'aa:bb:cc:dd',
    key_file    => $keyfile,
);
is $signer->key_id, 'ocid1.tenancy.oc1..aaaa/ocid1.user.oc1..bbbb/aa:bb:cc:dd',
   'key_id assembled';

# fingerprint can be derived from the key when not supplied
like $signer->key_fingerprint, qr/^([0-9a-f]{2}:){15}[0-9a-f]{2}$/,
     'derived fingerprint format';
my $auto = WebService::OCI::Signer->new(
    tenancy => 't', user => 'u', key_file => $keyfile);
like $auto->key_id, qr{^t/u/([0-9a-f]{2}:){15}[0-9a-f]{2}$},
     'fingerprint derived into key_id when omitted';

# alternate key inputs: a PEM string and a pre-loaded Crypt::PK::RSA object
my $pem = do { open my $f, '<', $keyfile or die "open $keyfile: $!"; local $/; <$f> };
my $s_pem = WebService::OCI::Signer->new(key_id => 't/u/f', private_key => $pem);
my $s_pk  = WebService::OCI::Signer->new(key_id => 't/u/f', pk => $pk);
is $s_pem->key_fingerprint, $signer->key_fingerprint, 'private_key (PEM string) loads same key';
is $s_pk->key_fingerprint,  $signer->key_fingerprint, 'pk (object) loads same key';

# error paths: no key at all, and signing without a key_id
eval { WebService::OCI::Signer->new(key_id => 't/u/f') };
like $@, qr/need private_key, key_file or pk/, 'missing key croaks';
eval { WebService::OCI::Signer->new(pk => $pk)->sign(method => 'GET', host => 'h', path => '/') };
like $@, qr/no key_id/, 'sign without a key_id croaks';
my $pubpem = $pk->export_key_pem('public');
my $pub    = Crypt::PK::RSA->new(\$pubpem);
eval { WebService::OCI::Signer->new(key_id => 't/u/f', pk => $pub) };
like $@, qr/not a private key/, 'a public-only key is rejected';

my $t     = 1700000000;
my $date  = WebService::OCI::Signer::_imf_date($t);
my $host  = 'iaas.us-ashburn-1.oraclecloud.com';
my $path  = '/20160918/instances';
my $query = 'compartmentId=ocid1.compartment.oc1..cccc';

# ---- GET ------------------------------------------------------------------
my ($h, $ss) = $signer->sign(
    method => 'GET', host => $host, path => $path, query => $query, time => $t);

is $ss, join("\n",
    "(request-target): get $path?$query",
    "host: $host",
    "date: $date",
), 'GET signing string is exact and in order';

is $h->{host}, $host, 'host header set';
is $h->{date}, $date, 'date header set';
like $h->{authorization},
     qr/^Signature version="1",keyId="\Q@{[$signer->key_id]}\E",algorithm="rsa-sha256",headers="\Q(request-target) host date\E",signature="[^"]+"$/,
     'authorization header shape (GET)';

my ($sig) = $h->{authorization} =~ /signature="([^"]+)"/;
ok $pk->verify_message(decode_base64($sig), $ss, 'SHA256', 'v1.5'),
   'GET signature verifies against the key';

# ---- POST with body -------------------------------------------------------
my $body = '{"cidrBlock":"10.0.0.0/16"}';
my ($hb, $ssb) = $signer->sign(
    method => 'POST', host => $host, path => '/20160918/vcns',
    body => $body, time => $t);

is $hb->{'x-content-sha256'}, encode_base64(sha256($body), ''), 'x-content-sha256';
is $hb->{'content-length'}, length($body), 'content-length';
is $hb->{'content-type'}, 'application/json', 'default content-type';
like $hb->{authorization},
     qr/headers="\Q(request-target) host date x-content-sha256 content-type content-length\E"/,
     'POST signs the body headers';

my ($sigb) = $hb->{authorization} =~ /signature="([^"]+)"/;
ok $pk->verify_message(decode_base64($sigb), $ssb, 'SHA256', 'v1.5'),
   'POST signature verifies';

# empty body still signs content-length 0 and sha256 of ""
my ($he) = $signer->sign(method => 'PUT', host => $host, path => '/x', time => $t);
is $he->{'content-length'}, 0, 'empty body content-length 0';
is $he->{'x-content-sha256'}, encode_base64(sha256(''), ''), 'empty body sha256';

# ---- sign_headers override (Object Storage PutObject style) ---------------
my ($ho, $sso) = $signer->sign(
    method => 'PUT', host => $host, path => '/n/ns/b/bkt/o/key',
    body => 'data', time => $t,
    sign_headers => [qw{ (request-target) host date }]);
like $ho->{authorization}, qr/headers="\Q(request-target) host date\E"/,
     'sign_headers override respected';
ok !exists $ho->{'content-length'}, 'no body headers added when overridden';
is $sso, join("\n",
    "(request-target): put /n/ns/b/bkt/o/key",
    "host: $host",
    "date: $date",
), 'overridden signing string';

done_testing;
