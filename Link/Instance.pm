
package Workflow::Link::Instance;

use strict;
use warnings;

class Workflow::Link::Instance {
    is_transactional => 0,
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'other_operation_instance_id' },
        property => { is => 'SCALAR' },
    ]
};

sub left_value {
    my $self = shift;
    
    return $self->operation_instance->output->{ $self->property };
}

1;
