
package Cord::Link;

use strict;
use warnings;

# links attach outputs to inputs

class Cord::Link {
    has => [
        workflow_model => { is => 'Cord::Model', id_by => 'workflow_model_id' },
        right_operation => { is => 'Cord::Operation', id_by => 'right_workflow_operation_id' },
        right_property => { is => 'BLOB' },
        left_operation => { is => 'Cord::Operation', id_by => 'left_workflow_operation_id' },
        left_property => { is => 'BLOB' },
        breakable => { is => 'Boolean', default_value => 0 }
    ]
};

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my %ops_by_name = map {
        $_->name => $_
    } $params{workflow_model}->operations;

    unless(exists $ops_by_name{$struct->{fromOperation}}) {
        Carp::confess('From operation not found: ' . $struct->{fromOperation});
    }

    unless(exists $ops_by_name{$struct->{fromOperation}}) {
        Carp::confess('To operation not found: ' . $struct->{toOperation});
    }

    my $self = $class->create(
        left_operation => $ops_by_name{$struct->{fromOperation}},
        left_property => $struct->{fromProperty},
        right_operation => $ops_by_name{$struct->{toOperation}},
        right_property => $struct->{toProperty},
        %params
    );

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {
        fromOperation => $self->left_operation->name,
        fromProperty => $self->left_property,
        toOperation => $self->right_operation->name,
        toProperty => $self->right_property
    };

    return $struct;
}

sub right_value {
    my $self = shift;
    my $dataset = shift;

    return $self->right_data($dataset)->input->{ $self->right_property };
}

sub left_value {
    my $self = shift;
    my $dataset = shift;

    return $self->left_data($dataset)->output->{ $self->left_property };
}

sub right_data {
    my $self = shift;
    my $dataset = shift;

    my $right_data = Cord::Operation::Instance->get(
        operation => $self->right_operation,
        model_instance => $dataset
    );

    return $right_data;
}

sub left_data {
    my $self = shift;
    my $dataset = shift;

    my $left_data = Cord::Operation::Instance->get(
        operation => $self->left_operation,
        model_instance => $dataset
    );

    return $left_data;
}

1;
