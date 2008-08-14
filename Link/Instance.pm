
package Workflow::Link::Instance;

use strict;
use warnings;

class Workflow::Link::Instance {
    is_transactional => 0,
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'other_operation_instance_id' },
        property => { is => 'SCALAR' },
        index => { is => 'INTEGER', is_optional=>1 },
    ]
};

sub clone {
    my $self = shift;
    return __PACKAGE__->create(
        operation_instance => $self->operation_instance,
        property => $self->property,
        @_
    );
}

sub left_value {
    my $self = shift;
    return $self->value;
}

sub raw_value {
    my $self = shift;
    
    return $self->operation_instance->output->{ $self->property };
}

sub value {
    my $self = shift;

    my $val = $self->raw_value;
    while (UNIVERSAL::isa($val,'Workflow::Link::Instance')) {
        $val = $val->value;
    }

    if (defined $self->index() && ref($val) eq 'ARRAY') {
        return $val->[ $self->index() ];
    } elsif (defined $self->index()) {
        warn $self->id . " has index but does not point toward ARRAY\n";
    }

    return $val;
}

1;
