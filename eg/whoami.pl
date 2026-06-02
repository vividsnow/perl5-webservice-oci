#!/usr/bin/perl
use strict;
use warnings;
use WebService::OCI;
use WebService::OCI::Config;
use Getopt::Long qw(:config no_auto_abbrev);

$| = 1;

# Confirm your config by showing the authenticated user and tenancy (Identity
# API) - a fuller check than the Object Storage namespace ping in first-call.pl.
#
#   perl eg/whoami.pl [--config FILE] [--profile DEFAULT]

my %o;
GetOptions(\%o, qw(config=s profile=s)) or die "bad options\n";

my $home = defined $ENV{HOME} ? $ENV{HOME} : $ENV{USERPROFILE};
my $file = defined $o{config} ? $o{config}
         : defined $ENV{OCI_CONFIG_FILE} ? $ENV{OCI_CONFIG_FILE}
         : defined $home ? "$home/.oci/config"
         : die "no --config and HOME is not set\n";
my %cfg = WebService::OCI::Config->load($file, $o{profile});

my $oci = WebService::OCI->new(
    service => 'identity',
    ($o{config}  ? (config_file => $o{config})  : ()),
    ($o{profile} ? (profile     => $o{profile}) : ()),
);

sub call {
    my ($res, $what) = @_;
    return $res if $res->is_success;
    my $b = $res->content;
    my $msg = ref $b eq 'HASH' ? "$b->{code}: $b->{message}" : ($b // '');
    die sprintf "%s failed: %s %s - %s\n", $what, $res->status, $res->reason // '', $msg;
}

my $user = call($oci->get("/20160918/users/$cfg{user}"),        'get user')->content;
my $ten  = call($oci->get("/20160918/tenancies/$cfg{tenancy}"), 'get tenancy')->content;

print "user:    $user->{name}  ($user->{lifecycleState})\n";
print "  email: ", $user->{email} // '-', "\n";
print "tenancy: $ten->{name}\n";
print "  home region key: ", $ten->{homeRegionKey} // '-', "\n";
print "region:  ", $cfg{region} // '-', "\n";
