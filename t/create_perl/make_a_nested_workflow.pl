#!/gsc/bin/perl

use strict;
use warnings;

use above 'Cord';
use Data::Dumper;

my $w_inner = Cord::Model->create(
    name => 'Example Inner Cord',
    input_properties => [ 'input string' ],
    output_properties => [ 'output string', 'result' ],
);
{
    my $echo = $w_inner->add_operation(
        name => 'echo',
        operation_type => Cord::Test::Command::Echo->operation
    );

    $w_inner->add_link(
        left_operation => $w_inner->get_input_connector,
        left_property => 'input string',
        right_operation => $echo,
        right_property => 'input',
    );
    $w_inner->add_link(
        left_operation => $echo,
        left_property => 'output',
        right_operation => $w_inner->get_output_connector,
        right_property => 'output string'
    );
    $w_inner->add_link(
        left_operation => $echo,
        left_property => 'result',
        right_operation => $w_inner->get_output_connector,
        right_property => 'result'
    );
}

my $w = Cord::Model->create(
    name => 'Example Cord',
    input_properties => ['test input'],
    output_properties => ['test output', 'result' ],
);

$w_inner->workflow_model($w);
    
    $w->add_link(
        left_operation => $w->get_input_connector,
        left_property => 'test input',
        right_operation => $w_inner,
        right_property => 'input string',
    );
    $w->add_link(
        left_operation => $w_inner,
        left_property => 'output string',
        right_operation => $w->get_output_connector,
        right_property => 'test output'
    );
    $w->add_link(
        left_operation => $w_inner,
        left_property => 'result',
        right_operation => $w->get_output_connector,
        right_property => 'result'
    );
    


#print $w->as_png("/tmp/test.png");
#print $w->as_text;
#exit;

my $out = $w->execute(
    'test input' => 'hello this is an echo test',
);

print Data::Dumper->new([$out])->Dump;

