#!/gsc/bin/perl

use strict;
use warnings;

use above 'Cord';
use Data::Dumper;

my $w = Cord::Model->create(
    name => 'Example Workflow',
    input_properties => [ 'model input string', 'sleep time' ],
    output_properties => [ 'model output string', 'today', 'result' ],
);
my $echo = $w->add_operation(
    name => 'echo',
    operation_type => Cord::Test::Command::Echo->operation
);
my $sleep = $w->add_operation(
    name => 'sleep',
    operation_type => Cord::Test::Command::Sleep->operation
);
my $time = $w->add_operation(
    name => 'time',
    operation_type => Cord::Test::Command::Time->operation
);
my $block = $w->add_operation(
    name => 'wait for sleep and echo',
    operation_type => Cord::OperationType::Block->create(
        properties => ['echo result','sleep result']
    ),
);
my $modelin = $w->get_input_connector;
my $modelout = $w->get_output_connector;

$w->add_link(
    left_operation => $modelin,
    left_property => 'model input string',
    right_operation => $echo, 
    right_property => 'input',
);
$w->add_link(
    left_operation => $modelin,
    left_property => 'sleep time',
    right_operation => $sleep,
    right_property => 'seconds',
);
$w->add_link(
    left_operation => $echo,
    left_property => 'output',
    right_operation => $modelout,
    right_property => 'model output string',
);
$w->add_link(
    left_operation => $sleep,
    left_property => 'result',
    right_operation => $block,
    right_property => 'sleep result',
);
$w->add_link(
    left_operation => $echo,
    left_property => 'result',
    right_operation => $block,
    right_property => 'echo result',
);
$w->add_link(
    left_operation => $block,
    left_property => 'echo result',
    right_operation => $modelout,
    right_property => 'result',
);
$w->add_link(
    left_operation => $time,
    left_property => 'today',
    right_operation => $modelout,
    right_property => 'today',
);

print $w->as_png("/tmp/test.png");

exit;

my $out = $w->execute(
    'model input string' => 'hello this is an echo test',
    'sleep time' => 3,
);

print Data::Dumper->new([$out])->Dump;

