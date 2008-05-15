
package Workflow::Operation;

use strict;
use warnings;

class Workflow::Operation {
    is_transactional => 0,
    has => [
        name => { is => 'Text' },
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        operation_type => { is => 'Workflow::OperationType', id_by => 'workflow_operationtype_id' },
        outputs => { is => 'HASH' },
        inputs => { is => 'HASH' },
        is_done => { }, 
    ]
};

sub is_ready {
    my $self = shift;

    my @required_inputs = @{ $self->operation_type->input_properties };
    my %current_inputs = ();
    if ( defined $self->inputs ) {
        %current_inputs = %{ $self->inputs };
    }

    my @unfinished_inputs = ();
    foreach my $input_name (@required_inputs) {
        if (exists $current_inputs{$input_name} && defined $current_inputs{$input_name}) {
            if (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link')) {
                unless ($current_inputs{$input_name}->left_operation->is_done && $current_inputs{$input_name}->left_value) {
                    push @unfinished_inputs, $input_name;
                }
            }
        } else {
            push @unfinished_inputs, $input_name;
        }
    }

    $self->status_message($self->name . " still needs: " . join(',', @unfinished_inputs))
        if (scalar @unfinished_inputs > 0);

    if (scalar @unfinished_inputs == 0) {
        return 1;
    } else {
        return 0;
    }
}

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my $self;

    ## i dont like this at all
    ## delegate sub-models
    if ($class eq __PACKAGE__ && $struct->{operationtype}->{typeClass} eq 'Workflow::OperationType::Model') {

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

sub execute {
    my $self = shift;

    my $operation_type = $self->operation_type;

    my %current_inputs = ();
    if ( defined $self->inputs ) {
        %current_inputs = %{ $self->inputs };
    }
    foreach my $input_name (keys %current_inputs) {
        if (UNIVERSAL::isa($current_inputs{$input_name},'Workflow::Link')) {
            $current_inputs{$input_name} = $current_inputs{$input_name}->left_value;
        }
    }

    my $old_outputs = $self->outputs || {};
    my $outputs = $operation_type->execute(%current_inputs);

    $self->outputs({%$old_outputs, %$outputs});

    $self->is_done(1);
    1;
}

1;
