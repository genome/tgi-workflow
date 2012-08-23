
package Workflow::Link;

use strict;
use warnings;

# links attach outputs to inputs

class Workflow::Link {
    has => [
        workflow_model => { is => 'Workflow::Model', id_by => 'workflow_model_id' },
        right_operation => { is => 'Workflow::Operation', id_by => 'right_workflow_operation_id' },
        right_property => { is => 'BLOB' },
        left_operation => { is => 'Workflow::Operation', id_by => 'left_workflow_operation_id' },
        left_property => { is => 'BLOB' },
        breakable => { is => 'Boolean', default_value => 0 }
    ]
};


my @_properties_for_add_link = ('id','workflow_model_id','left_workflow_operation_id','left_property',
                                'right_workflow_operation_id','right_property');
my @_properties_in_template_order;
my $_link_template;
my $_workflow_id_position;
my $_link_id_position;
sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my $ops_by_name = shift;
    my %params = (@_);

    Carp::confess unless ref $ops_by_name;

    unless(exists $ops_by_name->{$struct->{fromOperation}}) {
        Carp::confess('From operation not found: ' . $struct->{fromOperation});
    }

    unless(exists $ops_by_name->{$struct->{fromOperation}}) {
        Carp::confess('To operation not found: ' . $struct->{toOperation});
    }

    my $self;
    unless(exists $params{breakable}) { #speed up the case where "breakable is not specified"
        unless ($_link_template) {
            my $tmpl = UR::BoolExpr::Template->resolve('Workflow::Link', @_properties_for_add_link);
            unless ($tmpl) {
                Carp::croak('Cannot resolve BoolExpr template for adding Workflow::Link objects');
            }
            $tmpl = $tmpl->get_normalized_template_equivalent();
            for my $name ( @_properties_for_add_link ) {
                my $pos = $tmpl->value_position_for_property_name($name);
                if ($name eq 'workflow_model_id' ) {
                    $_workflow_id_position = $pos;
                } elsif ($name eq 'id') {
                    $_link_id_position = $pos;
                }
                $_properties_in_template_order[$pos] = $name;
            }
            $_link_template = $tmpl;
        }

        $params{left_workflow_operation_id} = $ops_by_name->{$struct->{fromOperation}}->id;
        $params{left_property} = $struct->{fromProperty};
        $params{right_workflow_operation_id} = $ops_by_name->{$struct->{toOperation}}->id;
        $params{right_property} = $struct->{toProperty};

        my @values = @params{@_properties_in_template_order};
        $values[$_workflow_id_position] = $params{workflow_model}->id;
        $values[$_link_id_position] = UR::Object::Type->autogenerate_new_object_id_urinternal();
        my $rule = $_link_template->get_rule_for_values(@values);
        $self = UR::Context->create_entity('Workflow::Link', $rule);

    } else {
        $self = $class->create(
            left_operation => $ops_by_name->{$struct->{fromOperation}},
            left_property => $struct->{fromProperty},
            right_operation => $ops_by_name->{$struct->{toOperation}},
            right_property => $struct->{toProperty},
            %params
        );
    }

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

    my $right_data = Workflow::Operation::Instance->get(
        operation => $self->right_operation,
        model_instance => $dataset
    );

    return $right_data;
}

sub left_data {
    my $self = shift;
    my $dataset = shift;

    my $left_data = Workflow::Operation::Instance->get(
        operation => $self->left_operation,
        model_instance => $dataset
    );

    return $left_data;
}

1;
