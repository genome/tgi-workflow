
package Workflow::Link::Instance;

use strict;
use warnings;

class Workflow::Link::Instance {
    has => [
        operation_instance => { is => 'Workflow::Operation::Instance', id_by => 'other_operation_instance_id' },
        property => { is => 'SCALAR' },
        index => { is => 'INTEGER', is_optional=>1 },
        broken => { is => 'Boolean', default_value => 0 },
        broken_value => { is_optional => 1 },
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

sub break {
    my $self = shift;
    my $value = shift;
    
    $self->broken(1);
    $self->broken_value($value);
    $self->index(undef);
    
    return $self;
}

sub left_value {
    my $self = shift;
    return $self->value;
}

sub raw_value {
    my $self = shift;
    
    if ($self->broken) {
        return $self->broken_value;
    } else {
        my $oi = $self->operation_instance;
        my $v = $oi->output->{ $self->property };
        unless ($v) {
            $v = $oi->input->{ $self->property };
        }
        return $v;
    }
}

sub value {
    my $self = shift;

    my $val = $self->raw_value;
    while (eval { $val->isa('Workflow::Link::Instance') }) {
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
