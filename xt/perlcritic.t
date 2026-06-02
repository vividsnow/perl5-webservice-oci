use strict;
use warnings;
use Test::More;

plan skip_all => 'set AUTHOR_TESTING or RELEASE_TESTING to run'
    unless $ENV{AUTHOR_TESTING} || $ENV{RELEASE_TESTING};

eval "use Test::Perl::Critic (-profile => 'xt/perlcriticrc')";
plan skip_all => "Test::Perl::Critic required: $@" if $@;

all_critic_ok('lib', 'bin');
