use strict;
use warnings;
use Test::More;

eval 'use Test::Pod::Coverage 1.08';
plan skip_all => 'Test::Pod::Coverage 1.08 required' if $@;
eval 'use Pod::Coverage 0.18';
plan skip_all => 'Pod::Coverage 0.18 required' if $@;

# .pod-only docs carry no code; coverage applies to the modules.
my @modules = grep { !/::(?:Guide|Cookbook)$/ } Test::Pod::Coverage::all_modules();
plan tests => scalar @modules;

# verb helpers and accessors are documented as grouped =item lists, whose
# first token is not the method name; trust them explicitly.
my %opts = (
    'WebService::OCI' => {
        trustme => [qr/^(?:get|head|delete|post|put|patch|signer|http|region)$/],
    },
);

pod_coverage_ok($_, $opts{$_} || {}, "$_ POD coverage") for @modules;
