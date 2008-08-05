
package Workflow::OperationType::Model;

use strict;
use warnings;

class Workflow::OperationType::Model {
    isa => 'Workflow::OperationType',
};

sub execute {
    Carp::confess("execute should not be called");
}

sub execute_XXX {
    my $self = shift;
    my %properties = @_;

    my $workflow_model = Workflow::Model->get(
        operation_type => $self
    );

    my $instance = $workflow_model->execute(
        input => \%properties
    );
    $workflow_model->wait;
    
    my $output = $instance->output;
    
    return $output;
}

1;
