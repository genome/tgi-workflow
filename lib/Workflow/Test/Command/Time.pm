package Cord::Test::Command::Time;

use strict;
use warnings;

use Cord;
use Command; 

class Cord::Test::Command::Time {
    is => ['Cord::Test::Command'],
    has_output => [
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
