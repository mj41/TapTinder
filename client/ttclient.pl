#!perl

use strict;
use warnings;

use Carp qw(carp croak verbose);
use FindBin qw($RealBin);
use Data::Dump qw(dump);

use File::Spec::Functions;
use File::Path;
use File::Copy;

# CPAN libs and own libs
use lib "$FindBin::Bin/../libcpan";
use lib "$FindBin::Bin/lib";

use YAML;

use Getopt::Long;
use Pod::Usage;

use TapTinder::Client;
use TapTinder::Client::Conf qw(load_client_conf);


# verbose level
#  >0 .. print errors only
#  >1 .. print base run info
#  >2 .. all run info (default)
#  >3 .. major debug info
#  >4 .. major and minor debug info
#  >5 .. all debug info

my $help = 0;
my $project_name = 'tt-test-proj';
my $conf_fpath = catfile( $RealBin, '..', 'client-conf', 'client-conf.yml' );
my $ver = 2; # verbosity level
my $debug = 1; # debug

my $options_ok = GetOptions(
    'help|h|?' => \$help,
    'project|p=s' => \$project_name,
    'conf_fpath|cfp=s' => \$conf_fpath,
    'verbose|v=i' => \$ver,
);
pod2usage(1) if $help || !$options_ok;

# TODO - Check parameters.
if ( $ver !~ /^\s*\d+\s*$/ || $ver < 0 || $ver > 5 ) {
    croak "Parameter error: ver is not 0-5.\n";
}

print "Verbose level: $ver\n" if $ver >= 3;
print "Working path: '" . $RealBin . "'\n" if $ver >= 4;

print "Loading config file for project '$project_name'.\n" if $ver >= 3;

my $client_conf = load_client_conf( $conf_fpath, $project_name );

# debug, will also dump passwd on screen
# dump( $client_conf ) if $ver >= 5;

print "Starting Client.\n" if $ver >= 3;
my $client = TapTinder::Client->new(
    $client_conf, $ver, $debug
);
$client->run();

exit;

__END__

=head1 NAME

ttclient - TapTinder client.

=head1 SYNOPSIS

ttclient [options]

 Options:
   --help
   --project ... Project name.
   --conf_fpath ... Config file path.
   --ver ... Verbose level, 0-5, default 2.

=head1 DESCRIPTION

B<This program> will start TapTinder client.

=cut