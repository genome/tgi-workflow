
package Workflow::OperationType::Model;

use strict;
use warnings;

class Workflow::OperationType::Model {
    isa => 'Workflow::OperationType',
};

sub execute {
    my $self = shift;
    my %properties = @_;

    my $workflow_model = Workflow::Model->get(
        operation_type => $self
    );

    return $workflow_model->execute(%properties);
 
}

1;
