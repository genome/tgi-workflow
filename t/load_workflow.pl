#!/gsc/bin/perl

use strict;
use warnings;

use above 'Cord';
use Data::Dumper;

my $w = Cord::Model->create_from_xml($ARGV[0] || 'sample.xml');

print join("\n", $w->validate) . "\n";

print $w->as_png("/tmp/test.png");

#my $out = $w->execute(
#    'model input string' => 'hello this is an echo test',
#    'sleep time' => 3,
#);

#print Data::Dumper->new([$out])->Dump;

