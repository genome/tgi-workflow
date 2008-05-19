#!/gsc/bin/perl

use strict;
use warnings;

use above 'Workflow';
use Data::Dumper;

my $w = Workflow::Model->create_from_xml($ARGV[0] || 'sample.xml');

my $out = $w->execute(
    'test input' => [qw/a b c d e f g/] 
);

print Data::Dumper->new([$out])->Dump;
#print join("\n", map { $_->name } $w->operations_in_series) . "\n";

#print join("\n", $w->validate) . "\n";

