use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

use ExtUtils::Manifest qw(manicheck filecheck);

my @missing = manicheck();
is_deeply \@missing, [], 'every file in MANIFEST exists on disk'
    or diag "missing: @missing";

my @extra = filecheck();   # honours MANIFEST.SKIP
is_deeply \@extra, [], 'every shipped file is listed in MANIFEST'
    or diag "not in MANIFEST: @extra";

done_testing;
