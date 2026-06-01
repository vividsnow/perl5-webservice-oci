use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'WebService::OCI',
    VERSION_FROM     => 'lib/WebService/OCI.pm',
    ABSTRACT_FROM    => 'lib/WebService/OCI.pm',
    AUTHOR           => 'vividsnow',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.010',
    EXE_FILES        => ['bin/oci-rest'],
    PREREQ_PM        => {
        'HTTP::Tiny'     => '0.070',
        'Crypt::PK::RSA' => '0',      # CryptX
        'JSON::PP'       => '0',
        'Digest::SHA'    => '0',
        'Digest::MD5'    => '0',
        'MIME::Base64'   => '0',
        'Getopt::Long'   => '0',      # bin/oci-rest
        'Carp'           => '0',
    },
    TEST_REQUIRES => {
        'Test::More' => '0.88',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        prereqs     => {
            runtime => {
                recommends => {
                    'IO::Socket::SSL'  => '1.56',
                    'Net::SSLeay'      => '1.49',
                    'Cpanel::JSON::XS' => '0',
                },
            },
        },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/vividsnow/perl5-webservice-oci.git',
                web  => 'https://github.com/vividsnow/perl5-webservice-oci',
            },
        },
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
    clean => { FILES => 'WebService-OCI-*' },
);
