package WebService::OCI::Config;
use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.01';

# Parse an ~/.oci/config style INI file and return the named profile as a hash.
# Keys recognised by WebService::OCI: tenancy, user, fingerprint, region,
# key_file, pass_phrase. Unknown keys are returned as-is.
sub load {
    my ($class, $file, $profile) = @_;
    $profile = 'DEFAULT' unless defined $profile;

    open my $fh, '<', $file or croak "cannot read OCI config '$file': $!";
    my %sect;
    my $cur = 'DEFAULT';            # keys before any [section] land in DEFAULT
    while (my $line = <$fh>) {
        $line =~ s/\r?\n\z//;
        $line =~ s/^\s+//;
        next if $line eq '' || $line =~ /^[#;]/;
        if ($line =~ /^\[([^\]]+)\]\s*$/) { $cur = $1; next }
        my ($k, $v) = split /=/, $line, 2;
        next unless defined $v;
        for ($k, $v) { s/^\s+//; s/\s+$//; }   # trim both ends of key and value
        $sect{$cur}{$k} = $v;
    }
    close $fh;

    my $p = $sect{$profile}
        or croak "OCI config '$file' has no profile '$profile'";

    my %cfg = %$p;
    $cfg{key_file} = _expand_home($cfg{key_file}) if defined $cfg{key_file};
    return %cfg;
}

sub _expand_home {
    my ($path) = @_;
    my $home = defined $ENV{HOME} ? $ENV{HOME} : $ENV{USERPROFILE};
    $path =~ s{^~(?=/|\z)}{$home} if defined $home;
    return $path;
}

1;

__END__

=head1 NAME

WebService::OCI::Config - read ~/.oci/config profiles

=head1 SYNOPSIS

    use WebService::OCI::Config;
    my %cfg = WebService::OCI::Config->load("$ENV{HOME}/.oci/config", 'DEFAULT');
    # %cfg: tenancy, user, fingerprint, region, key_file, pass_phrase, ...

=head1 DESCRIPTION

A small dependency-free INI reader for the OCI CLI/SDK config file. Used by
L<WebService::OCI> when no explicit credentials are passed to the constructor.

The file is divided into C<[PROFILE]> sections; keys before the first section
header belong to C<DEFAULT>. Blank lines and C<#>/C<;> comments are ignored,
and whitespace around C<=> is trimmed. A leading C<~> in C<key_file> is
expanded to the home directory.

=head1 METHODS

=head2 load

    my %cfg = WebService::OCI::Config->load($file, $profile);

Reads C<$file> and returns the named C<$profile> (default C<DEFAULT>) as a hash
of its keys: typically C<tenancy>, C<user>, C<fingerprint>, C<region>,
C<key_file> and C<pass_phrase>. Croaks if the file cannot be read or the
profile is absent.

=head1 SEE ALSO

L<WebService::OCI>, L<WebService::OCI::Guide>

=head1 AUTHOR

vividsnow

=head1 LICENSE

This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
