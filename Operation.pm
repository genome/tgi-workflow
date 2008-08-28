
package Workflow::Operation;

use strict;
use warnings;

class Workflow::Operation {
    is_transactional => 0,
    has => [
        name => { is => 'Text' },
        workflow_model => { is => 'UR::Object', id_by => 'workflow_model_id' },
        operation_type => { is => 'Workflow::OperationType', id_by => 'workflow_operationtype_id' },
        is_valid => { is => 'Boolean', doc => 'Flag set when validate has run' },
        executor => { is => 'Workflow::Executor', id_by => 'workflow_executor_id', is_optional => 1 },
        parallel_by => { is => 'String' },
    ]
};

sub dependent_operations {
    my $self = shift;
    
    my %operations = map {
        $_->right_operation->id => $_->right_operation
    } Workflow::Link->get(left_operation => $self);
    
    return values %operations;
}

sub depended_on_by {
    my $self = shift;
    
    my %operations = map {
        $_->left_operation->id => $_->left_operation
    } Workflow::Link->get(right_operation => $self);
    
    return values %operations;
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

sub validate {
    my ($self) = @_;
    
    $self->is_valid(1);
    return ();
}

sub operations_in_series {
    my $self = shift;

    return ($self);
}

sub execute {
    my $self = shift;
    my %params = (@_);

    unless ($self->is_valid) {
        my @errors = $self->validate;
        unless (@errors == 0) {
            die 'cannot execute invalid workflow';
        }
    }
    
    unless (exists $params{store} && $params{store} && $params{store}->can('sync')) {
        $params{store} = Workflow::Store::None->create();
    }

    {
        my %ikeys = map { $_ => 1 } keys %{ $params{input} };
        foreach my $k (@{ $self->operation_type->input_properties }) {
            delete $ikeys{$k} if exists $ikeys{$k};
        }

        if (scalar keys %ikeys) {
            Carp::croak('execute: Extra inputs provided');
            return;
        }
    }

    my $operation_instance = Workflow::Operation::Instance->create(
        operation => $self,
        store => $params{store},
        output_cb => $params{output_cb}
    );
    $operation_instance->input($params{input} || {});
    $operation_instance->output({});

    $operation_instance->sync;
    $operation_instance->execute;

    return $operation_instance;
}

sub wait {
    my $self = shift;
    
    $self->executor->wait($self);
}

sub detach {
    my $self = shift;
    
    $self->executor->detach($self);
}

1;
