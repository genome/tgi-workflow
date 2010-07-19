package Workflow::Test::Command::DeprecatedOperationDefinition;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::DeprecatedOperationDefinition {
    is => ['Workflow::Test::Command'],
    has => [
        today => { 
            calculate => q|
                return UR::Time->today;
            |,
        },
        now => {
            calculate => q|
                return UR::Time->now;
            |,
        },
    ],
};

operation_io Workflow::Test::Command::DeprecatedOperationDefinition {
    input  => [ ],
    output => [ 'today', 'now' ],
    lsf_resource => 'rusage[tmp=100]',
    lsf_queue => 'long'
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
