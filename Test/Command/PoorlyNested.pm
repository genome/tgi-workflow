package Workflow::Test::Command::PoorlyNested;

use strict;
use warnings;

use Workflow;
use Workflow::Simple;

class Workflow::Test::Command::PoorlyNested {
    is => ['Workflow::Test::Command'],
    has => [
        input => { 
            doc => 'input',
            is_input => 1
        },
        output => { 
            doc => 'output',
            is_optional => 1,
            is_output => 1
        }, 
    ],
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Sleeps for the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test sleep --seconds=5 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;


    my $op = Workflow::Operation->create(
        name => 'poorly nested',
        operation_type => Workflow::OperationType::Command->get('Workflow::Test::Command::Echo')
    );

    $op->parallel_by('input');

    my @input = map { $self->input . ' ' . $_ } qw/ab cd ef gh ij kl mn op qr st uv wx yz/;
    my $out = run_workflow_lsf($op, input => \@input);

    return 0 unless $out;

    $self->output($out->{output});

    1;
}
 
1;
