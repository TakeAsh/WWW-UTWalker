use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";

use_ok $_ for qw(
    WWW::YTWalker
);

done_testing;

