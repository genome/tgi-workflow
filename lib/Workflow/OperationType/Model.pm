
package Workflow::OperationType::Model;

use strict;
use warnings;

class Workflow::OperationType::Model {
    isa => 'Workflow::OperationType',
};

sub execute {
    Carp::confess("execute should not be called");
}

1;
