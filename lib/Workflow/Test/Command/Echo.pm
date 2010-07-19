package Workflow::Test::Command::Echo;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Echo {
    is => ['Workflow::Test::Command'],
    has => [
        input => { 
            doc => 'input',
            is_input => 1
        },
        output => { 
            doc => 'output',
            calculate_from => ['input'],
            calculate => q|
                return "$input";
            |,
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

    1;
}
 
1;
