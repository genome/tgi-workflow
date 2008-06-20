
package Workflow::Operation;

use strict;
use warnings;

class Workflow::Operation {
    is_transactional => 0,
    has => [
        name => { is => 'Text' },
        workflow_model => { is => 'UR::Object', id_by => 'workflow_model_id' },
        operation_type => { is => 'Workflow::OperationType', id_by => 'workflow_operationtype_id' },
    ]
};

sub dependent_operations {
    my $self = shift;
    
    my @operations = map {
        $_->right_operation
    } Workflow::Link->get(left_operation => $self);
    
    return @operations;
}

sub depended_on_by {
    my $self = shift;
    
    my @operations = map {
        $_->left_operation
    } Workflow::Link->get(right_operation => $self);
    
    return @operations;
}

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my $self;

    ## i dont like this at all
    ## delegate sub-models
    if ($class eq __PACKAGE__ && (exists $struct->{operationtype} && $struct->{operationtype}->{typeClass} eq 'Workflow::OperationType::Model' || $struct->{workflowFile})) {

        $self = Workflow::Model->create_from_xml_simple_structure($struct,%params);
    } else {
        my $optype = Workflow::OperationType->create_from_xml_simple_structure($struct->{operationtype});
        $self = $class->create(
            name => $struct->{name},
            operation_type => $optype,
            %params
        );
    }

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {
        name => $self->name,
        operationtype => $self->operation_type->as_xml_simple_structure
    };

    return $struct;
}

#
# This delegates to the executor after fixing up some inputs
sub execute {
    my ($self, $data) = (shift,shift);

    my $operation_type = $self->operation_type;

    ## rewrite inputs
    my %current_inputs = ();
    foreach my $input_name (keys %{ $data->input }) {
        if (UNIVERSAL::isa($data->input->{$input_name},'Workflow::Link::Instance')) {
            $current_inputs{$input_name} = $data->input->{$input_name}->left_value;
        }
    }

    my $executor = $self->workflow_model->executor;
    
    if ($operation_type->can('executor') && defined $operation_type->executor) {
        $executor = $operation_type->executor;
    }
    
    $executor->execute(
        operation_instance => $data,
        edited_input => \%current_inputs
    );
    
    return $data;
}

1;
