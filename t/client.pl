#!/gsc/bin/perl

use strict;
use above 'Workflow';
use Workflow::Client;
use POE;

my @pipeline_outputs = ();

foreach my $i (qw/a/) {

Workflow::Client->execute_workflow(
    xml_file => 'xml.d/00_basic.xml',
    input => {
        'model input string' => 'hello this is echo test: ' . $i,
        'sleep time' => 1
    },
    output_cb => sub {
        my ($data) = @_;
        push @pipeline_outputs, $data->output;
    },
    no_run => 1
);

}

POE::Kernel->run();

print Data::Dumper->new(\@pipeline_outputs)->Dump;

