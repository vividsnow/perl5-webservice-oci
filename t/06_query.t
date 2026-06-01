use strict;
use warnings;
use Test::More;
use WebService::OCI;

# query string construction (pure functions)
is WebService::OCI::_build_query(undef), '', 'undef query -> empty';
is WebService::OCI::_build_query('a=1&b=2'), 'a=1&b=2', 'string passed through verbatim';
is WebService::OCI::_build_query({ b => 2, a => 1 }), 'a=1&b=2', 'hashref sorted by key';
is WebService::OCI::_build_query([ z => 1, a => 2 ]), 'z=1&a=2', 'arrayref preserves order';
is WebService::OCI::_build_query({ q => 'a b/c:d' }), 'q=a%20b%2Fc%3Ad',
   'RFC3986 encoding (space=%20, reserved escaped)';
is WebService::OCI::_build_query({ flag => undef }), 'flag',
   'undef value -> bare key';
is WebService::OCI::_build_query({ flag => '' }), 'flag=',
   'empty-string value -> key= (distinct from a bare key)';
is WebService::OCI::_build_query({ 'k+y' => 'v=w' }), 'k%2By=v%3Dw',
   'both key and value are encoded';

# unreserved set is left intact
is WebService::OCI::_uri_escape('AZaz09-._~'), 'AZaz09-._~', 'unreserved chars untouched';

done_testing;
