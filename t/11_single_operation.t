#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;
use Workflow;

require_ok('Workflow::Operation');

my $w = Workflow::Operation->create(
    name => 'echo',
    operation_type => Workflow::Test::Command::Echo->operation_type,
    executor => Workflow::Executor::SerialDeferred->get()
);
ok($w,'add echo operation');
isa_ok($w,'Workflow::Operation');

ok(do {
    $w->validate;
    $w->is_valid;
},'validate');

my $output;
my $collector = sub {
    my $data = shift;
    
    $output = $data->output;
};

ok($w->execute(
    input => {
        'input' => 'abracadabra321'
    },
    output_cb => $collector
),'execute workflow');

ok($w->wait,'wait for completion');

is_deeply(
    $output,
    {
        'output' => 'abracadabra321',
        'result' => 1
    },
    'check output'
);

ok($w->parallel_by('input'),'set parallel');

ok($w->execute(
    input => {
        'input' => ['abcd','efgh','hijk']
    },
    output_cb => $collector
),'execute parallel workflow');

ok($w->wait,'wait for completion');

is_deeply(
    $output,
    {
        'output' => ['abcd','efgh','hijk'],
        'result' => [1,1,1]
    },
    'check parallel output'
);
