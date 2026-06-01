use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval 'use Test::Kwalitee 1.21 qw(kwalitee_ok)';
plan skip_all => 'Test::Kwalitee 1.21 required' if $@;

# META.* and the packaged-dist metrics only exist after `make dist`; skip those
# so this runs meaningfully against the source tree.
kwalitee_ok(qw(
    -has_meta_yml
    -has_meta_json
    -metayml_is_parsable
    -metayml_has_license
    -metayml_declares_perl_version
    -manifest_matches_dist
));

done_testing;
