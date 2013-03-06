use strict;
use warnings;

use Test::More tests => 3;
use Cwd qw(realpath);
use File::Basename qw(dirname);
use File::Spec;

my $annotate_log = realpath(File::Spec->join(dirname(__FILE__), '..', 'bin', 'annotate-log'));
ok(-e $annotate_log, 'found annotate-log');

my $false = system($annotate_log, 'false') >> 8;
isnt($false, 0, '`annotate-log false` returned non-zero');

my $true = system($annotate_log, 'true') >> 8;
is($true, 0, '`annotate-log true` returned zero');
