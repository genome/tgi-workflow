package Workflow::Test::Command::Time;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Time {
    is => ['Workflow::Test::Command'],
    has_output => [
        today => { 
            calculate => q|
                return Workflow::Time->today;
            |,
        },
        now => {
            calculate => q|
                return Workflow::Time->now;
            |,
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
