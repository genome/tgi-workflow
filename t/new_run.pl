#!/gsc/bin/perl

use strict;
use warnings;

use above 'Workflow';
use Data::Dumper;

my $w = Workflow::Model->create_from_xml($ARGV[0] || 'xml.d/00_basic.xml');

my @foo = qw/ab cd ef/;

my @pipeline_inputs = map {
    my %hash = (
        'model input string' => $_,
        'sleep time' => 1,
    );
    \%hash;
} @foo;
my @pipeline_outputs = ();

my $callback = sub {
    my ($data) = (@_);
    push @pipeline_outputs, $data->output;
};

foreach my $inputs (@pipeline_inputs) {
    my $result = $w->execute(
        input => $inputs,
        output_cb => $callback    
    );
}

$w->wait;

print Data::Dumper->new(\@pipeline_outputs)->Dump;
