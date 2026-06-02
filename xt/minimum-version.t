use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval 'use Test::MinimumVersion 0.008';
plan skip_all => 'Test::MinimumVersion 0.008 required' if $@;

# the distribution declares 5.010 (Makefile.PL / cpanfile); make sure no file
# actually requires anything newer
all_minimum_version_ok('5.010');
