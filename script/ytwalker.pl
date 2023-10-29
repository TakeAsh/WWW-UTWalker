#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Getopt::Long;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::YTWalker;
use Term::Encoding qw(term_encoding);
use open ':std' => ':utf8';

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $channels = 0;
my $logLevel = 'notice';
my $notMatch = 0;
my $schedule = 0;
my %opts     = ( 'log' => \$logLevel, 'notMatch' => \$notMatch, 'schedule' => \$schedule );
GetOptions(
    \%opts,
    'channels' => \$channels,
    'log=s', 'notMatch', 'schedule',
);

if ($channels) {
    showChannels();
} else {
    YTWalker( \%opts, \@ARGV );
}
