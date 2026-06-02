package WebService::OCI;
use strict;
use warnings;
use Carp qw(croak);
use HTTP::Tiny;
use WebService::OCI::Signer;
use WebService::OCI::Config;

our $VERSION = '0.01';

sub _json {
    for my $mod (qw(Cpanel::JSON::XS JSON::XS)) {
        return $mod->new->utf8->canonical->allow_nonref
            if eval "require $mod; 1";
    }
    require JSON::PP;
    return JSON::PP->new->utf8->canonical->allow_nonref;
}

sub _default_config_path {
    return $ENV{OCI_CONFIG_FILE} if defined $ENV{OCI_CONFIG_FILE};
    my $home = defined $ENV{HOME} ? $ENV{HOME} : $ENV{USERPROFILE};
    return defined $home ? "$home/.oci/config" : undef;
}

sub new {
    my ($class, %a) = @_;

    my %cfg;
    my $have_creds = defined $a{key_id}
        || defined $a{private_key}
        || defined $a{key_file}
        || (defined $a{tenancy} && defined $a{user});
    if ($a{config_file} || !$have_creds) {
        my $file = defined $a{config_file} ? $a{config_file} : _default_config_path();
        if (defined $file && -r $file) {
            %cfg = WebService::OCI::Config->load($file, $a{profile});
        }
        elsif (defined $a{config_file}) {
            croak "OCI config file not readable: $a{config_file}";
        }
    }

    my $tenancy     = defined $a{tenancy}     ? $a{tenancy}     : $cfg{tenancy};
    my $user        = defined $a{user}        ? $a{user}        : $cfg{user};
    my $fingerprint = defined $a{fingerprint} ? $a{fingerprint} : $cfg{fingerprint};
    my $region      = defined $a{region}      ? $a{region}      : $cfg{region};
    my $key_file    = defined $a{key_file}    ? $a{key_file}    : $cfg{key_file};
    my $passphrase  = defined $a{passphrase}  ? $a{passphrase}
                    : defined $cfg{pass_phrase} ? $cfg{pass_phrase} : $cfg{passphrase};

    my $signer = WebService::OCI::Signer->new(
        (defined $a{key_id}
            ? (key_id => $a{key_id})
            : (tenancy => $tenancy, user => $user,
               (defined $fingerprint ? (fingerprint => $fingerprint) : ()))),
        (defined $a{private_key}
            ? (private_key => $a{private_key})
            : (key_file => $key_file)),
        (defined $passphrase ? (passphrase => $passphrase) : ()),
    );

    my $http = $a{http} || HTTP::Tiny->new(
        agent      => defined $a{agent} ? $a{agent} : "WebService-OCI/$VERSION",
        timeout    => defined $a{timeout} ? $a{timeout} : 60,
        keep_alive => 1,
        verify_SSL => defined $a{verify_SSL} ? $a{verify_SSL} : 1,
    );

    return bless {
        signer   => $signer,
        http     => $http,
        region   => $region,
        service  => $a{service},
        base_url => $a{base_url},
        trace    => $a{trace},
        json     => _json(),
    }, $class;
}

sub signer { $_[0]{signer} }
sub http   { $_[0]{http} }
sub region { $_[0]{region} }

# percent-encode per RFC 3986 (space -> %20, not '+')
sub _uri_escape {
    my ($s) = @_;
    return '' unless defined $s;
    utf8::encode($s) if utf8::is_utf8($s);
    $s =~ s/([^A-Za-z0-9\-._~])/sprintf '%%%02X', ord $1/ge;
    return $s;
}

# query may be a string (used verbatim), hashref (sorted) or arrayref (ordered)
sub _build_query {
    my ($q) = @_;
    return '' unless defined $q;
    return $q unless ref $q;
    my @pairs;
    if (ref $q eq 'ARRAY') {
        my @a = @$q;
        while (@a >= 2) { push @pairs, [ splice @a, 0, 2 ] }
    }
    else {
        @pairs = map { [ $_, $q->{$_} ] } sort keys %$q;
    }
    return join '&', map {
        my ($k, $v) = @$_;
        _uri_escape($k) . (defined $v ? '=' . _uri_escape($v) : '');
    } @pairs;
}

sub _endpoint {
    my ($self, $a) = @_;
    my $base = defined $a->{base_url} ? $a->{base_url} : $self->{base_url};
    if (!defined $base) {
        my $svc = defined $a->{service} ? $a->{service} : $self->{service};
        croak 'no service or base_url given' unless defined $svc;
        if ($svc =~ m{^https?://}i) { $base = $svc }
        elsif ($svc =~ /\./)        { $base = "https://$svc" }
        else {
            my $region = defined $a->{region} ? $a->{region} : $self->{region};
            croak "region required to build endpoint for service '$svc'"
                unless defined $region;
            $base = "https://$svc.$region.oraclecloud.com";
        }
    }
    $base =~ s{/+$}{};
    my $scheme = $base =~ m{^(https?)://}i ? lc $1 : 'https';
    (my $host = $base) =~ s{^https?://}{}i;
    $host =~ s{/.*$}{}s;
    my $default_port = $scheme eq 'http' ? 80 : 443;
    $host =~ s{:$default_port$}{};   # omit default port, matching HTTP::Tiny's Host
    return ($base, $host);
}

sub request {
    my ($self, %a) = @_;
    my $method = uc(defined $a{method} ? $a{method} : 'GET');
    my ($base, $host) = $self->_endpoint(\%a);
    my $path = defined $a{path} ? $a{path} : '/';
    $path = "/$path" unless $path =~ m{^/};
    my $query = _build_query($a{query});
    my $url = $base . $path . (length $query ? "?$query" : '');

    my $body;
    if    (exists $a{json}) { $body = $self->{json}->encode($a{json}) }
    elsif (exists $a{body}) { $body = $a{body} }
    my $is_body = $method eq 'POST' || $method eq 'PUT' || $method eq 'PATCH';
    $body = '' if $is_body && !defined $body;
    # a wide-character body would make content-length and x-content-sha256
    # disagree with the octets HTTP::Tiny sends; sign and send the same bytes
    utf8::encode($body) if defined $body && utf8::is_utf8($body);

    # lower-case header keys up front so a caller's "Content-Type" is seen here
    # (and cannot collide with an injected lowercase key once the signer
    # lower-cases everything for the signature)
    my %h = map { lc($_) => $a{headers}{$_} } keys %{ $a{headers} || {} };
    $h{'content-type'} = 'application/json'
        if exists $a{json} && !defined $h{'content-type'};

    my ($headers, $signing_string) = $self->{signer}->sign(
        method => $method, host => $host, path => $path, query => $query,
        body => $body, headers => \%h,
        ($a{sign_headers} ? (sign_headers => $a{sign_headers}) : ()),
        (defined $a{time}  ? (time => $a{time}) : ()),
    );

    $self->{trace}->({
        method => $method, url => $url, headers => $headers,
        signing_string => $signing_string, body => $body,
    }) if $self->{trace};

    # HTTP::Tiny derives Host from the URL and rejects it as a header option;
    # it stays in the (already computed) signature, so just drop it here.
    my %send = %$headers;
    delete $send{host};

    my %opt = (headers => \%send);
    $opt{content} = $body if defined $body;

    my $res = $self->{http}->request($method, $url, \%opt);
    return WebService::OCI::Response->new($res, $self->{json});
}

sub get    { my ($s, $p, %a) = @_; $s->request(method => 'GET',    path => $p, %a) }
sub head   { my ($s, $p, %a) = @_; $s->request(method => 'HEAD',   path => $p, %a) }
sub delete { my ($s, $p, %a) = @_; $s->request(method => 'DELETE', path => $p, %a) }

sub post {
    my ($s, $p, $d, %a) = @_;
    $s->request(method => 'POST', path => $p, (defined $d ? (json => $d) : ()), %a);
}

sub put {
    my ($s, $p, $d, %a) = @_;
    $s->request(method => 'PUT', path => $p, (defined $d ? (json => $d) : ()), %a);
}

sub patch {
    my ($s, $p, $d, %a) = @_;
    $s->request(method => 'PATCH', path => $p, (defined $d ? (json => $d) : ()), %a);
}

# ---- lightweight response wrapper -----------------------------------------
package WebService::OCI::Response;

sub new { bless { r => $_[1], json => $_[2] }, $_[0] }

sub status     { $_[0]{r}{status} }
sub success    { $_[0]{r}{success} }
sub is_success { $_[0]{r}{success} }
sub reason     { $_[0]{r}{reason} }
sub headers    { $_[0]{r}{headers} }
sub raw        { $_[0]{r}{content} }

sub _content_type {
    my $ct = $_[0]{r}{headers}{'content-type'};
    $ct = $ct->[0] if ref $ct eq 'ARRAY';
    return defined $ct ? $ct : '';
}

# decoded body when JSON, raw string otherwise
sub content {
    my ($self) = @_;
    my $c = $self->{r}{content};
    if (defined $c && length $c && _content_type($self) =~ m{application/json}i) {
        my $d = eval { $self->{json}->decode($c) };
        return $d unless $@;
    }
    return $c;
}

sub json { $_[0]{json}->decode($_[0]{r}{content}) }

1;

__END__

=head1 NAME

WebService::OCI - minimal, fast Oracle Cloud Infrastructure (OCI) REST client

=head1 SYNOPSIS

    use WebService::OCI;

    # credentials from ~/.oci/config (DEFAULT profile)
    my $oci = WebService::OCI->new(service => 'iaas');

    # ...or explicitly
    my $oci = WebService::OCI->new(
        tenancy     => 'ocid1.tenancy.oc1..aaaa',
        user        => 'ocid1.user.oc1..bbbb',
        fingerprint => 'aa:bb:cc:dd:...',
        key_file    => '/home/me/.oci/oci_api_key.pem',
        region      => 'us-ashburn-1',
        service     => 'iaas',
    );

    # GET any endpoint (this is a thin generic client, not a per-service SDK)
    my $r = $oci->get('/20160918/instances',
        query => { compartmentId => $compartment_id });
    die $r->reason unless $r->is_success;
    my $instances = $r->content;          # decoded JSON (arrayref)

    # POST with a JSON body (Content-Type, x-content-sha256, length handled)
    my $r2 = $oci->post('/20160918/vcns',
        { compartmentId => $cid, cidrBlock => '10.0.0.0/16' });

=head1 DESCRIPTION

A small, dependency-light client for the Oracle Cloud Infrastructure REST API.
The hard part of OCI is not breadth of methods but B<correct request signing>;
this module pairs the signer (L<WebService::OCI::Signer>) with a thin
L<HTTP::Tiny> transport and a generic L</request> method that can reach B<any>
OCI endpoint. It is deliberately not an auto-generated, per-service SDK: you
pass the path and parameters from Oracle's API reference and get back the
decoded JSON.

Performance comes from L<HTTP::Tiny> keep-alive (one TLS connection reused
across calls) and from skipping heavier user-agent stacks. Calls are
synchronous; RSA-SHA256 signing per request is negligible next to the round
trip.

New to OCI? Read L<WebService::OCI::Guide> for a from-scratch walkthrough
(generate a key, find your OCIDs, write a config, make your first call), then
L<WebService::OCI::Cookbook> for task-oriented recipes. A command-line front
end, L<oci-rest>, ships with this distribution.

=head1 CONSTRUCTOR

=head2 new

    my $oci = WebService::OCI->new(%args);

Credentials are taken from explicit arguments first, then from the config file.
If no credential arguments are given at all, the config file is read
automatically.

Credential arguments:

=over 4

=item *

C<key_id>, or C<tenancy> + C<user> + C<fingerprint>. When C<fingerprint> is
omitted it is derived from the key.

=item *

C<key_file> (path) or C<private_key> (PEM string), with optional C<passphrase>.

=item *

C<region> - used to build endpoints from a service name.

=item *

C<config_file> (default C<$OCI_CONFIG_FILE> or F<~/.oci/config>) and C<profile>
(default C<DEFAULT>).

=back

Other arguments: C<service> and C<base_url> set per-call defaults; C<timeout>
(seconds), C<verify_SSL> (default true), C<agent> (User-Agent string); C<http>
injects your own L<HTTP::Tiny>-compatible object (useful for testing); C<trace>
is a coderef called before each request with a hashref of C<method>, C<url>,
C<headers>, C<signing_string> and C<body> (this is what C<oci-rest --debug>
uses).

=head1 METHODS

=head2 request

    my $res = $oci->request(%args);

The general entry point. Recognised arguments:

=over 4

=item *

C<method> - HTTP method (default C<GET>).

=item *

C<path> - request path, used verbatim; pre-encode any reserved characters in
path segments yourself.

=item *

C<query> - a query string used as-is, a hashref (encoded with sorted keys), or
an arrayref of C<< key =E<gt> value >> pairs (order preserved). Values are
percent-encoded per RFC 3986.

=item *

C<json> - a data structure to encode as a JSON body, or C<body> for raw bytes.

=item *

C<headers> - extra request headers (hashref).

=item *

C<service> / C<base_url> - override the endpoint for this call.

=item *

C<region> - override the region used to build the endpoint for this call.

=item *

C<sign_headers> - override the set of signed headers, for example
C<['(request-target)','host','date']> for Object Storage PutObject.

=item *

C<time> - epoch seconds for the C<date> header, for reproducible tests only
(see L<WebService::OCI::Signer/sign>).

=back

Returns a L<WebService::OCI::Response>.

=head2 HTTP verb helpers

Thin wrappers around L</request>.

=over 4

=item C<< $oci->get($path, %args) >>

=item C<< $oci->head($path, %args) >>

=item C<< $oci->delete($path, %args) >>

The above send no body.

=item C<< $oci->post($path, $payload, %args) >>

=item C<< $oci->put($path, $payload, %args) >>

=item C<< $oci->patch($path, $payload, %args) >>

C<$payload>, when defined, is sent as a JSON body. For a raw body pass
C<undef> for C<$payload> and a C<body> argument instead.

=back

=head2 Accessors

=over 4

=item C<< $oci->signer >>

The underlying L<WebService::OCI::Signer>.

=item C<< $oci->http >>

The underlying L<HTTP::Tiny> (or injected) object.

=item C<< $oci->region >>

The configured region, if any.

=back

=head1 ENDPOINTS

A bare service name builds
C<https://E<lt>serviceE<gt>.E<lt>regionE<gt>.oraclecloud.com> - correct for
common services such as C<iaas> (Compute, Networking, Block Volume),
C<objectstorage> and C<identity>. A C<service> that contains a dot is treated
as a full host, and C<base_url> overrides everything.

Use C<base_url> for anything that does not fit the simple pattern: other realms
(for example Government Cloud, whose hosts end in C<oraclegovcloud.com>), or any
service whose host has a different shape. No service-to-host table is hardcoded,
so a wrong host is never silently assumed; when in doubt, copy the base URL from
Oracle's API reference for the service and pass it as C<base_url>.

=head1 RESPONSE

L</request> and the verb helpers return a B<WebService::OCI::Response> object:

=over 4

=item C<is_success> (alias C<success>)

True for a 2xx status. HTTP::Tiny reports transport failures as status 599.

=item C<status>

Numeric HTTP status.

=item C<reason>

HTTP reason phrase, or the error message on a transport failure.

=item C<headers>

Response headers as a hashref (lower-cased keys).

=item C<content>

The body decoded from JSON when the response Content-Type is JSON, otherwise
the raw string.

=item C<json>

Force-decode the body as JSON regardless of Content-Type. Unlike C<content>,
this dies if the body is empty or not valid JSON, so use C<content> when the
body may be absent (for example a HEAD or 204 response).

=item C<raw>

The undecoded response body.

=back

=head1 AUTHENTICATION

Only API-key (request-signing) authentication is supported, which is the
C<~/.oci/config> scheme used by the OCI CLI and SDKs. Instance principals,
resource principals and session-token auth are out of scope.

=head1 ERRORS

Constructing the client C<die>s on unusable credentials (missing key, etc).
A completed HTTP exchange never dies: check L</is_success> and inspect
L</status>, L</reason> and L</content>. OCI error bodies are JSON with C<code>
and C<message> fields, and the C<opc-request-id> response header is what Oracle
support needs when investigating a failure.

=head1 ENVIRONMENT

=over 4

=item C<OCI_CONFIG_FILE>

Default config file path when C<config_file> is not given.

=back

=head1 CAVEATS

Calls are synchronous and a client handles one request at a time; the
keep-alive connection and the signer are stateful, so give each concurrent
worker its own client rather than sharing one. There is no built-in retry,
backoff, or pagination - you loop yourself (OCI rate-limits with HTTP 429 and
paginates lists with the C<opc-next-page> header; see
L<WebService::OCI::Cookbook>). As a thin generic client it does not validate
paths or parameters against a service model - you pass them straight from
Oracle's API reference.

=head1 SEE ALSO

L<WebService::OCI::Guide>, L<WebService::OCI::Cookbook>,
L<WebService::OCI::Signer>, L<WebService::OCI::Config>, L<oci-rest>,
L<HTTP::Tiny>, L<Crypt::PK::RSA>.

Oracle's REST API reference: L<https://docs.oracle.com/en-us/iaas/api/>

=head1 AUTHOR

vividsnow

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
