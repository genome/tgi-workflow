
package Workflow::Executor;

use strict;

class Workflow::Executor {
    is => 'UR::Singleton',
    is_transactional => 0,
    is_abstract => 1
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
