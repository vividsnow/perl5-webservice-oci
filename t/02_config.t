use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);
use WebService::OCI::Config;

my ($fh, $file) = tempfile(UNLINK => 1);
print {$fh} <<'INI';
# sample oci config
[DEFAULT]
user=ocid1.user.oc1..default
fingerprint = aa:bb:cc:dd
tenancy=ocid1.tenancy.oc1..default
region = us-ashburn-1
key_file = ~/.oci/oci_api_key.pem
pass_phrase=secret

[STAGING]
user = ocid1.user.oc1..staging
tenancy = ocid1.tenancy.oc1..staging
region = eu-frankfurt-1
key_file = /abs/key.pem
INI
close $fh;

local $ENV{HOME} = '/home/tester';

my %d = WebService::OCI::Config->load($file, 'DEFAULT');
is $d{user},        'ocid1.user.oc1..default', 'DEFAULT user';
is $d{fingerprint}, 'aa:bb:cc:dd',             'value trimmed around =';
is $d{region},      'us-ashburn-1',            'DEFAULT region';
is $d{pass_phrase}, 'secret',                  'pass_phrase';
is $d{key_file}, '/home/tester/.oci/oci_api_key.pem', '~ expanded to HOME';

my %s = WebService::OCI::Config->load($file, 'STAGING');
is $s{tenancy},  'ocid1.tenancy.oc1..staging', 'STAGING tenancy';
is $s{key_file}, '/abs/key.pem',               'absolute key_file untouched';

# default profile is DEFAULT
my %def = WebService::OCI::Config->load($file);
is $def{region}, 'us-ashburn-1', 'default profile is DEFAULT';

eval { WebService::OCI::Config->load($file, 'NOPE') };
like $@, qr/no profile 'NOPE'/, 'missing profile croaks';

# unreadable / missing file croaks
eval { WebService::OCI::Config->load('/no/such/oci/config/here', 'DEFAULT') };
like $@, qr/cannot read OCI config/, 'unreadable file croaks';

# a line without '=' is skipped; an empty value is kept
my ($fh2, $file2) = tempfile(UNLINK => 1);
print {$fh2} <<'INI';
[DEFAULT]
garbage line without equals
user = ocid1.user.oc1..x
empty_value =
INI
close $fh2;
my %p = WebService::OCI::Config->load($file2, 'DEFAULT');
is $p{user}, 'ocid1.user.oc1..x', 'valid key parsed despite a junk line above it';
ok !exists $p{'garbage line without equals'}, 'line without = is skipped';
is $p{empty_value}, '', 'empty value kept as empty string';

done_testing;
