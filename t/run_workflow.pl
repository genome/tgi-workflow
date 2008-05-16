#!/gsc/bin/perl

use strict;
use warnings;

use above 'Workflow';
use Data::Dumper;

my $w = Workflow::Model->create_from_xml($ARGV[0] || 'sample.xml');

my $out = $w->execute(
    'model input string' => 'hello this is an echo test',
    'sleep time' => 3,
);

print Data::Dumper->new([$out])->Dump;

