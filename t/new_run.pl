#!/gsc/bin/perl

use strict;
use warnings;

use above 'Workflow';
use Data::Dumper;

UR::Observer->register_callback(
    subject_class_name => 'Workflow::Executor::SerialDeferred',
    aspect => 'count',
    callback => sub {
        my ($self) = @_;
        print $self->id . ' ' . $self->count . "\n";
    },
);

my $w = Workflow::Model->create_from_xml($ARGV[0] || 'xml.d/00_basic.xml');

$w->executor->limit(1);

my @foo = qw/ab/;

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
    print Data::Dumper->new([$data->current])->Dump;
    push @pipeline_outputs, $data->output;
};

foreach my $inputs (@pipeline_inputs) {
    my $result = $w->execute(
        input => $inputs,
        output_cb => $callback,    
        store => Workflow::Store::Db->create()
    );
}

eval {

    $w->wait;
};
if ($@) {
    warn "$@\n";
}
UR::Context->commit();

print Data::Dumper->new([$w,\@pipeline_outputs])->Dump;
