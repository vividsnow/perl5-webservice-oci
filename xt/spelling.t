use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval 'use Test::Spelling 0.20';
plan skip_all => 'Test::Spelling 0.20 required' if $@;
plan skip_all => 'no working spellchecker (aspell/hunspell/ispell)'
    unless has_working_spellchecker();

add_stopwords(<DATA>);
all_pod_files_spelling_ok(qw(lib bin));

__DATA__
OCI
OCID
OCIDs
oci
rest
API
APIs
SDK
SDKs
REST
RSA
SHA
MD5
TLS
SSL
JSON
PEM
DER
HTTP
HTTPS
JMESPath
namespace
namespaces
objectstorage
iaas
tenancy
tenancy's
fingerprint
cavage
oraclecloud
oraclegovcloud
oci_api_key
passphrase
config
keepalive
keep
keyId
opc
ETag
etag
lifecycleState
CryptX
HTTPTiny
runtime
unencoded
pre
walkthrough
PutObject
UploadPart
GetNamespace
ListCompartments
vividsnow
prepended
percent
subcommand
subcommands
stdin
config's
lookup
lowercased
POSTs
async
auth
fixdate
undecoded
NotAuthenticated
NotFound
UA
backend
realm
realms
decodes
hardcoded
versioned
VCN
VNIC
VNICs
vnic
vnicId
vnicAttachments
subnet
subnetId
assignPublicIp
sourceDetails
createVnicDetails
shapeConfig
ocpus
memoryInGBs
imageId
instanceId
availabilityDomain
availabilityDomains
ssh
opc
sortBy
sortOrder
RUNNING
PROVISIONING
Micro
Flex
OCPU
OCPUs
Ampere
SDKs
SDK
unauthenticated
SCIM
preview
checkout
KEYFILE
STR
param
params
JMESPath
