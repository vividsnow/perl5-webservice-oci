use strict;
use warnings;
use Test::More;
use FindBin;
use WebService::OCI;

# capture-and-canned-response HTTP::Tiny stand-in
package FakeUA;
sub new  { bless { calls => [], resp => undef }, shift }
sub last { $_[0]{calls}[-1] }
sub request {
    my ($self, $method, $url, $opt) = @_;
    push @{ $self->{calls} }, { method => $method, url => $url, opt => $opt };
    return $self->{resp} || {
        success => 1, status => 200, reason => 'OK',
        headers => { 'content-type' => 'application/json' },
        content => '{"ok":true}',
    };
}

package main;

my $keyfile = "$FindBin::Bin/testkey.pem";
my $ua = FakeUA->new;
my %trace;
my $oci = WebService::OCI->new(
    tenancy     => 'ocid1.tenancy.oc1..aaaa',
    user        => 'ocid1.user.oc1..bbbb',
    fingerprint => 'aa:bb',
    key_file    => $keyfile,
    region      => 'us-ashburn-1',
    service     => 'iaas',
    http        => $ua,
    trace       => sub { %trace = %{ $_[0] } },
);

# ---- GET with query (sorted keys, RFC3986 escaping) -----------------------
$ua->{resp} = {
    success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => 'application/json' },
    content => '{"x":1}',
};
my $r = $oci->get('/20160918/instances',
    query => { compartmentId => 'ocid1..c', displayName => 'a b' });

is $ua->last->{method}, 'GET', 'GET method';
is $ua->last->{url},
   'https://iaas.us-ashburn-1.oraclecloud.com/20160918/instances?compartmentId=ocid1..c&displayName=a%20b',
   'endpoint built, query sorted and percent-encoded (space=%20)';
ok $ua->last->{opt}{headers}{authorization}, 'authorization header sent';
ok $ua->last->{opt}{headers}{date},          'date header sent';
# Host must NOT be sent as a header option (HTTP::Tiny derives it and dies
# otherwise) - but it must still be in the signed string.
ok !exists $ua->last->{opt}{headers}{host},
   'Host not passed as a header option';
like $trace{signing_string}, qr/^host: \Qiaas.us-ashburn-1.oraclecloud.com\E$/m,
   'endpoint host is in the signed string';
ok !exists $ua->last->{opt}{content}, 'no body on GET';

ok $r->is_success, 'response is_success';
is $r->status, 200, 'status';
is_deeply $r->content, { x => 1 }, 'JSON body decoded';

# ---- POST encodes JSON body and signs body headers ------------------------
$oci->post('/20160918/vcns', { compartmentId => 'c', cidrBlock => '10.0.0.0/16' });
is $ua->last->{method}, 'POST', 'POST method';
is $ua->last->{opt}{content}, '{"cidrBlock":"10.0.0.0/16","compartmentId":"c"}',
   'JSON body, canonical key order';
is $ua->last->{opt}{headers}{'content-type'}, 'application/json', 'content-type';
ok $ua->last->{opt}{headers}{'x-content-sha256'}, 'x-content-sha256 sent';
is $ua->last->{opt}{headers}{'content-length'}, length($ua->last->{opt}{content}),
   'content-length matches body';

# ---- per-call service override (full prefix builds host) ------------------
$oci->get('/n', service => 'objectstorage');
is $ua->last->{url}, 'https://objectstorage.us-ashburn-1.oraclecloud.com/n',
   'per-call service override';

# ---- base_url override (arbitrary host / alternate realm) -----------------
$oci->get('/n',
    base_url => 'https://objectstorage.us-langley-1.oraclegovcloud.com');
is $ua->last->{url},
   'https://objectstorage.us-langley-1.oraclegovcloud.com/n',
   'base_url override reaches an arbitrary host / realm';
like $trace{signing_string},
   qr/^host: \Qobjectstorage.us-langley-1.oraclegovcloud.com\E$/m,
   'signed host matches base_url';
ok !exists $ua->last->{opt}{headers}{host}, 'Host still not sent as header option';

# ---- non-JSON response returns raw content --------------------------------
$ua->{resp} = {
    success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => 'text/plain' },
    content => 'plain text',
};
is $oci->get('/x')->content, 'plain text', 'non-JSON content returned raw';
is $oci->get('/x')->raw,     'plain text', 'raw() returns the undecoded body';

# ---- a JSON content-type with an undecodable body falls back to the raw string
$ua->{resp} = {
    success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => 'application/json' },
    content => 'not json{',
};
is $oci->get('/x')->content, 'not json{', 'invalid JSON body falls back to raw';

# ---- error response surfaces status/reason and decodes the OCI error body --
$ua->{resp} = {
    success => '', status => 404, reason => 'Not Found',
    headers => { 'content-type' => 'application/json' },
    content => '{"code":"NotAuthorizedOrNotFound","message":"nope"}',
};
my $err = $oci->get('/missing');
ok !$err->is_success, 'error response is not is_success';
is $err->status, 404, 'error status';
is $err->reason, 'Not Found', 'error reason';
is $err->content->{code}, 'NotAuthorizedOrNotFound', 'decoded error body';

# ---- json() force-decodes regardless of Content-Type ----------------------
$ua->{resp} = {
    success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => 'text/plain' },
    content => '{"ns":"abc"}',
};
is_deeply $oci->get('/x')->json, { ns => 'abc' }, 'json() decodes despite text/plain';

# json() is strict: an empty body (HEAD/204) decodes-dies, while content() is lenient
$ua->{resp} = { success => 1, status => 204, reason => 'No Content',
    headers => {}, content => '' };
my $empty = $oci->get('/x');
is $empty->content, '', 'content() returns an empty body as-is';
ok !eval { $empty->json; 1 }, 'json() dies on an empty body';

# a multi-valued Content-Type (arrayref, as some user-agents return) decodes
$ua->{resp} = {
    success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => ['application/json'] },
    content => '{"a":1}',
};
is_deeply $oci->get('/x')->content, { a => 1 },
   'arrayref content-type header still decodes JSON';

# ---- verb helpers wire method and body correctly --------------------------
$ua->{resp} = { success => 1, status => 200, reason => 'OK', headers => {}, content => '' };
$oci->delete('/d');
is $ua->last->{method}, 'DELETE', 'delete method';
ok !exists $ua->last->{opt}{content}, 'delete sends no body';
$oci->head('/h');
is $ua->last->{method}, 'HEAD', 'head method';
$oci->put('/p', { a => 1 });
is $ua->last->{method}, 'PUT', 'put method';
is $ua->last->{opt}{content}, '{"a":1}', 'put encodes JSON body';
$oci->patch('/p', { b => 2 });
is $ua->last->{method}, 'PATCH', 'patch method';
is $ua->last->{opt}{content}, '{"b":2}', 'patch encodes JSON body';

# ---- sign_headers override (Object Storage PutObject) through request() ----
$oci->put('/n/ns/b/bkt/o/key', undef,
    body         => 'rawbytes',
    headers      => { 'content-type' => 'application/octet-stream' },
    sign_headers => [qw{ (request-target) host date }]);
is $ua->last->{opt}{content}, 'rawbytes', 'raw body sent verbatim';
ok !exists $ua->last->{opt}{headers}{'x-content-sha256'},
   'no x-content-sha256 when sign_headers is overridden';
like $ua->last->{opt}{headers}{authorization},
   qr/headers="\Q(request-target) host date\E"/, 'only the overridden headers are signed';

# ---- mixed-case Content-Type + json: deterministic, single value ----------
$oci->post('/p', { x => 1 },
    headers => { 'Content-Type' => 'application/merge-patch+json' });
is $ua->last->{opt}{headers}{'content-type'}, 'application/merge-patch+json',
   'caller Content-Type (any case) wins over the json default';
is_deeply [ grep { lc eq 'content-type' } keys %{ $ua->last->{opt}{headers} } ],
   ['content-type'], 'exactly one content-type key (no case-variant collision)';

# ---- endpoint resolution: per-call region and dotted-service-as-host ------
$ua->{resp} = { success => 1, status => 200, reason => 'OK',
    headers => { 'content-type' => 'application/json' }, content => '{}' };
$oci->get('/n', service => 'objectstorage', region => 'eu-frankfurt-1');
is $ua->last->{url}, 'https://objectstorage.eu-frankfurt-1.oraclecloud.com/n',
   'per-call region override';
$oci->get('/x', service => 'iaas.us-ashburn-1.oraclecloud.com');
is $ua->last->{url}, 'https://iaas.us-ashburn-1.oraclecloud.com/x',
   'a service containing a dot is used as a full host';

# ---- endpoint resolution error paths --------------------------------------
my $bare = WebService::OCI->new(
    key_id => 't/u/f', key_file => $keyfile, http => FakeUA->new);
eval { $bare->get('/x') };
like $@, qr/no service or base_url/, 'no service/base_url croaks';
eval { $bare->get('/x', service => 'iaas') };
like $@, qr/region required/, 'bare service without region croaks';

# ---- an explicit, unreadable config_file croaks in the constructor --------
eval { WebService::OCI->new(config_file => '/no/such/oci/file', key_file => $keyfile) };
like $@, qr/not readable/, 'unreadable explicit config_file croaks';

# ---- constructor options reach the underlying HTTP::Tiny ------------------
my $real = WebService::OCI->new(
    key_id => 't/u/f', key_file => $keyfile,
    agent => 'demo-agent/9', timeout => 17, verify_SSL => 0);
isa_ok $real->http, 'HTTP::Tiny', 'default transport';
is $real->http->agent,   'demo-agent/9', 'agent reaches HTTP::Tiny';
is $real->http->timeout, 17,             'timeout reaches HTTP::Tiny';
ok !$real->http->verify_SSL, 'verify_SSL => 0 reaches HTTP::Tiny';
my $dflt = WebService::OCI->new(key_id => 't/u/f', key_file => $keyfile);
ok $dflt->http->verify_SSL, 'verify_SSL defaults on';
ok $dflt->http->keep_alive, 'keep_alive on';

done_testing;
