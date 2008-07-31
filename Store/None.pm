
package Workflow::Store::None;

use strict;

class Workflow::Store::None {
    isa => 'Workflow::Store',
    is_transactional => 0
};

sub sync {
    my ($self, $operation_instance) = @_;
    
    return 1;
}

1;
