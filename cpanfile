requires 'perl', '5.010';

requires 'HTTP::Tiny',     '0.070';
requires 'Crypt::PK::RSA', '0';      # provided by CryptX
requires 'JSON::PP',       '0';
requires 'Digest::SHA',    '0';
requires 'Digest::MD5',    '0';
requires 'MIME::Base64',   '0';
requires 'Getopt::Long',   '0';     # bin/oci-rest
requires 'Carp',           '0';

# HTTPS transport and a faster JSON codec when available
recommends 'IO::Socket::SSL',  '1.56';
recommends 'Net::SSLeay',      '1.49';
recommends 'Cpanel::JSON::XS', '0';

on test => sub {
    requires 'Test::More', '0.88';
};
