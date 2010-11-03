
package Cord::OperationType::Model;

use strict;
use warnings;

class Cord::OperationType::Model {
    isa => 'Cord::OperationType',
};

sub execute {
    Carp::confess("execute should not be called");
}

1;
