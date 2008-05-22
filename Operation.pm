
package Workflow::Operation;

use strict;
use warnings;

class Workflow::Operation {
    is_transactional => 0,
    has => [
        name => { is => 'Text' },
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
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
    my $self = shift;
    my %params = @_;
    
    my $data = $params{operation_data};
    my $operation_type = $self->operation_type;
    my $callback = $params{output_cb};

    ## rewrite inputs
    my %current_inputs = ();
    foreach my $input_name (keys %{ $data->input }) {
        if (UNIVERSAL::isa($data->input->{$input_name},'Workflow::Link')) {
            $current_inputs{$input_name} = $data->input->{$input_name}->left_value($data->dataset);
        }
    }

    $self->workflow_model->executor->execute(
        operation => $self,
        operation_data => $data,
        edited_input => \%current_inputs,
        output_cb => $callback
    );
    
    return $data;
}

1;
