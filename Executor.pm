
package Workflow::Executor;

use strict;

class Workflow::Executor {
    has => [
    ]
};

sub exception {
    my ($self,$instance,$message) = @_;
    
    $instance->sync;
    
    die ($message);
}

sub wait {
    1;
}

1;
