package Workflow::Test::Command::Watchdog;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Watchdog {
    is => ['Workflow::Test::Command'],
    has_input => [
        seconds => { 
            is => 'Integer', 
            is_optional => 1, 
            doc => 'length in seconds to sleep'
        },
    ],
    has_param => [
        lsf_queue => {
            default_value => 'short',
        },
        lsf_resource => {
            default_value => 'rusage[mem=4000] span[hosts=1]',
        }
    ]
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

    my $dog = Workflow::Server::Watchdog->create( duration => 30 );

    if ($self->seconds) {
        sleep $self->seconds;
    }

    $dog->delete;

    1;
}
 
1;
