use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval 'use Test::Synopsis';
plan skip_all => 'Test::Synopsis required' if $@;

all_synopsis_ok();
