use strict;
use warnings;
use Test::More;
use WebService::OCI;

# Live smoke test against a real tenancy. Skipped unless configured.
# Set TEST_OCI_LIVE=1 and either rely on ~/.oci/config (DEFAULT) or set
# TEST_OCI_CONFIG / TEST_OCI_PROFILE / TEST_OCI_REGION.
plan skip_all => 'set TEST_OCI_LIVE=1 to run live OCI smoke test'
    unless $ENV{TEST_OCI_LIVE};

my $oci = WebService::OCI->new(
    (defined $ENV{TEST_OCI_CONFIG}  ? (config_file => $ENV{TEST_OCI_CONFIG}) : ()),
    (defined $ENV{TEST_OCI_PROFILE} ? (profile     => $ENV{TEST_OCI_PROFILE}) : ()),
    (defined $ENV{TEST_OCI_REGION}  ? (region      => $ENV{TEST_OCI_REGION})  : ()),
);

# Object Storage GetNamespace: authenticated, needs no compartment id.
my $r = $oci->get('/n', service => 'objectstorage');
ok $r->is_success, 'GetNamespace succeeded'
    or diag "status=@{[$r->status]} reason=@{[$r->reason]} body=@{[$r->raw]}";
ok defined $r->content, 'got a namespace' if $r->is_success;
diag 'namespace: ' . $r->content if $r->is_success;

done_testing;
