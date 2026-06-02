use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval 'use Test::CPAN::Changes';
plan skip_all => 'Test::CPAN::Changes required' if $@;

changes_file_ok();
done_testing;
