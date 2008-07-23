
package Workflow::Store::None;

use strict;

class Workflow::Store::None {
    isa => 'Workflow::Store',
    is_transactional => 0
};

sub sync {
    my ($self, $model_instance) = @_;
    
    return 1;
}

1;
