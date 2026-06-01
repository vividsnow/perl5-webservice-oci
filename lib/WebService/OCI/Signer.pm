package WebService::OCI::Signer;
use strict;
use warnings;
use Carp qw(croak);
use MIME::Base64 qw(encode_base64);
use Digest::SHA qw(sha256);
use Crypt::PK::RSA;

our $VERSION = '0.01';

# draft-cavage-http-signatures header sets, as required by OCI API-key auth.
my @SIGN_GET  = ('(request-target)', 'host', 'date');
my @SIGN_BODY = ('(request-target)', 'host', 'date',
                 'x-content-sha256', 'content-type', 'content-length');

# locale-independent IMF-fixdate (RFC 7231): "Thu, 01 Jan 1970 00:00:00 GMT"
my @DOW = qw(Sun Mon Tue Wed Thu Fri Sat);
my @MON = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

sub _imf_date {
    my $t = defined $_[0] ? $_[0] : time;
    my @g = gmtime $t;            # sec min hour mday mon year wday yday isdst
    return sprintf '%s, %02d %s %04d %02d:%02d:%02d GMT',
        $DOW[$g[6]], $g[3], $MON[$g[4]], $g[5] + 1900, $g[2], $g[1], $g[0];
}

sub _fingerprint {
    my ($pk) = @_;
    require Digest::MD5;
    my $h = Digest::MD5::md5_hex($pk->export_key_der('public'));
    $h =~ s/(..)(?=.)/$1:/g;
    return $h;
}

sub new {
    my ($class, %a) = @_;

    my $pk = $a{pk};
    if (!$pk) {
        if (defined $a{private_key}) {
            $pk = Crypt::PK::RSA->new(\$a{private_key},
                (defined $a{passphrase} ? $a{passphrase} : ()));
        }
        elsif (defined $a{key_file}) {
            $pk = Crypt::PK::RSA->new($a{key_file},
                (defined $a{passphrase} ? $a{passphrase} : ()));
        }
        else {
            croak 'WebService::OCI::Signer: need private_key, key_file or pk';
        }
    }
    croak 'WebService::OCI::Signer: key is not a private key'
        unless $pk->is_private;

    # key_id may stay undef (e.g. fingerprint-only use); sign() enforces it
    my $key_id = $a{key_id};
    if (!defined $key_id && defined $a{tenancy} && defined $a{user}) {
        my $f = defined $a{fingerprint} ? $a{fingerprint} : _fingerprint($pk);
        $key_id = "$a{tenancy}/$a{user}/$f";
    }

    return bless { pk => $pk, key_id => $key_id }, $class;
}

sub key_id          { $_[0]{key_id} }
sub key_fingerprint { _fingerprint($_[0]{pk}) }

# sign(%request) -> \%headers  (or (\%headers, $signing_string) in list context)
#
# request keys: method, host, path, query (encoded string), body (bytes),
#               headers (\%), sign_headers (\@ override), time (epoch)
sub sign {
    my ($self, %req) = @_;
    croak 'sign: signer has no key_id (need key_id or tenancy+user)'
        unless defined $self->{key_id};
    my $method = lc($req{method} // croak 'sign: method required');
    my $host   = $req{host}      // croak 'sign: host required';
    my $path   = defined $req{path} ? $req{path} : '/';
    my $query  = $req{query};

    # work on a lowercased copy of caller headers
    my %h;
    while (my ($k, $v) = each %{ $req{headers} || {} }) { $h{ lc $k } = $v }

    my $target = $path;
    $target .= '?' . $query if defined $query && length $query;

    $h{host} = $host                       unless defined $h{host};
    $h{date} = _imf_date($req{time})       unless defined $h{date};

    my $is_body = $method eq 'post' || $method eq 'put' || $method eq 'patch';
    my @names;
    if ($req{sign_headers}) {
        @names = @{ $req{sign_headers} };
    }
    elsif ($is_body) {
        my $body = defined $req{body} ? $req{body} : '';
        $h{'x-content-sha256'} = encode_base64(sha256($body), '')
            unless defined $h{'x-content-sha256'};
        $h{'content-type'}   = 'application/json' unless defined $h{'content-type'};
        $h{'content-length'} = length $body       unless defined $h{'content-length'};
        @names = @SIGN_BODY;
    }
    else {
        @names = @SIGN_GET;
    }

    my %sign = %h;
    $sign{'(request-target)'} = "$method $target";

    my $signing_string = join "\n", map {
        croak "sign: missing header '$_' required by signature" unless defined $sign{$_};
        "$_: $sign{$_}";
    } @names;

    my $sig = encode_base64(
        $self->{pk}->sign_message($signing_string, 'SHA256', 'v1.5'), '');

    $h{authorization} = sprintf
        'Signature version="1",keyId="%s",algorithm="rsa-sha256",headers="%s",signature="%s"',
        $self->{key_id}, join(' ', @names), $sig;

    return wantarray ? (\%h, $signing_string) : \%h;
}

1;

__END__

=head1 NAME

WebService::OCI::Signer - sign Oracle Cloud Infrastructure API requests

=head1 SYNOPSIS

    use WebService::OCI::Signer;

    my $signer = WebService::OCI::Signer->new(
        tenancy     => 'ocid1.tenancy.oc1..aaaa',
        user        => 'ocid1.user.oc1..bbbb',
        fingerprint => 'aa:bb:cc:...',     # optional, derived from key if omitted
        key_file    => '/path/to/oci_api_key.pem',
        # or: private_key => $pem_string, passphrase => $pw
        # or: key_id => "$tenancy/$user/$fingerprint"
    );

    my $headers = $signer->sign(
        method => 'GET',
        host   => 'iaas.us-ashburn-1.oraclecloud.com',
        path   => '/20160918/instances',
        query  => 'compartmentId=ocid1.compartment.oc1..cccc',
    );
    # %$headers now has host, date and authorization ready to send

=head1 DESCRIPTION

Implements the OCI API-key request-signing scheme (HTTP Signatures,
draft-cavage-http-signatures-08, RSA-SHA256). This is the part that must be
byte-exact or the service answers 401; it is kept standalone so it can be
reused with any HTTP client.

The signed header set depends on the method. GET, HEAD and DELETE sign
C<(request-target)>, C<host> and C<date>. POST, PUT and PATCH additionally sign
(and, if absent, compute) C<x-content-sha256> (base64 SHA-256 of the body, even
when the body is empty), C<content-type> (default C<application/json>) and
C<content-length>. Pass C<sign_headers> to override the set entirely - for
example Object Storage PutObject signs only C<(request-target) host date>.

The C<date> header is generated as a locale-independent RFC 7231 IMF-fixdate.
The signing string is the chosen headers as C<< name: value >> lines joined by
newlines (no trailing newline), with C<(request-target)> being the lower-cased
method, a space, and the path with query string.

=head1 METHODS

=head2 new

    my $signer = WebService::OCI::Signer->new(%args);

Arguments: a key as C<key_file> (path), C<private_key> (PEM string) or C<pk>
(a L<Crypt::PK::RSA> object), with optional C<passphrase>; and an identity as
C<key_id> or C<tenancy> + C<user> (+ optional C<fingerprint>, derived from the
key when omitted). The C<key_id> may be left unset for fingerprint-only use,
but then L</sign> will croak.

=head2 sign

    my $headers              = $signer->sign(%request);
    my ($headers, $sigstring) = $signer->sign(%request);

Signs a request and returns the headers to send (C<host>, C<date>, the body
headers where applicable, and C<authorization>). Request keys: C<method>,
C<host>, C<path>, C<query> (an already-encoded string), C<body> (bytes),
C<headers> (extra headers, hashref), C<sign_headers> (override) and C<time>
(epoch seconds, mainly for testing). In list context also returns the exact
signing string.

=head2 key_id

The C<keyId> used in the Authorization header
(C<< tenancy/user/fingerprint >>), or undef.

=head2 key_fingerprint

The API key fingerprint derived from the key: the colon-separated hex MD5 of
the DER-encoded public key, identical to
C<< openssl rsa -pubout -outform DER | openssl md5 -c >> and to the fingerprint
the OCI Console shows when you upload the public key.

=head1 SEE ALSO

L<WebService::OCI>, L<WebService::OCI::Guide>, L<Crypt::PK::RSA>

=head1 AUTHOR

vividsnow

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
