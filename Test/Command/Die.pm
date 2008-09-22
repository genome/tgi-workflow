package Workflow::Test::Command::Die;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Die {
    is => ['Workflow::Test::Command'],
    has => [
        seconds => { is => 'Integer', is_optional => 1, doc => 'length in seconds to sleep before dying' },
    ],
};

operation_io Workflow::Test::Command::Die {
    input  => [ 'seconds' ],
    output => []
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "dies after the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test die --seconds=5 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;
   
    if ($self->seconds) {
        sleep $self->seconds;
    }
    
    die 'death by test case' unless defined $::DONT_DIE;

    1;
}
 
1;
