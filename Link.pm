
package Workflow::Link;

use strict;
use warnings;

# links attach outputs to inputs

class Workflow::Link {
    is_transactional => 0,
    has => [
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        right_operation => { is => 'Workflow::Operation', id_by => 'right_workflow_operation_id' },
        right_property => { is => 'BLOB' },
        left_operation => { is => 'Workflow::Operation', id_by => 'left_workflow_operation_id' },
        left_property => { is => 'BLOB' },
    ]
};

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my %ops_by_name = map {
        $_->name => $_
    } $params{workflow_model}->operations;

    my $self = $class->create(
        right_operation => $ops_by_name{$struct->{fromOperation}},
        right_property => $struct->{fromProperty},
        left_operation => $ops_by_name{$struct->{toOperation}},
        left_property => $struct->{toProperty},
        %params
    );

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {
        fromOperation => $self->right_operation->name,
        fromProperty => $self->right_property,
        toOperation => $self->left_operation->name,
        toProperty => $self->left_property
    };

    return $struct;
}

sub set_inputs {
    my $self = shift;

    my $current_inputs = $self->right_operation->inputs || {};

    $self->right_operation->inputs({ 
        %{ $current_inputs }, 
        $self->right_property => $self
    });
}

sub right_value {
    my $self = shift;

    my $right_outputs = $self->right_operation->outputs;
    return $right_outputs->{$self->right_property} if ($right_outputs);
    return undef;
}

sub left_value {
    my $self = shift;

    my $left_outputs = $self->left_operation->outputs;
    return $left_outputs->{$self->left_property} if ($left_outputs);
    return undef;
}

1;
