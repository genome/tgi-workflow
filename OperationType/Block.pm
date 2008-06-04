
package Workflow::OperationType::Block;

use strict;
use warnings;

class Workflow::OperationType::Block {
    isa => 'Workflow::OperationType',
    has => [
        executor => { is => 'Workflow::Executor' },
    ]
};

sub create_from_xml_simple_structure {
    my ($class,$struct) = @_;

    my $serial_executor = Workflow::Executor::Serial->create;

    my $self = $class->create(
        properties => $struct->{property}
    );
    
    $self->executor($serial_executor);

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;

    # this operationtype has cloned inputs and outputs
    $struct->{property} = delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub create {
    my $self = shift;
    my %args = @_;
    
    unless ($args{properties}) { 
        $self->error_message("property list not provided");
        return;
    }
    
    return $self->SUPER::create(
        input_properties => \@{ $args{properties} },
        output_properties => \@{ $args{properties} },
    );
}

sub execute {
    my $self = shift;
    my %properties = @_;

    my %outputs = ();
    foreach my $output_property (@{ $self->output_properties }) {
        $outputs{$output_property} = $properties{$output_property};
    }

    return \%outputs;
}


1;
