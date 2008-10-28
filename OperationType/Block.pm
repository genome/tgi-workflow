
package Workflow::OperationType::Block;

use strict;
use warnings;

class Workflow::OperationType::Block {
    isa => 'Workflow::OperationType',
    has => [
        stay_in_process => {
            value => 1
        }
    ]
};

sub create_from_xml_simple_structure {
    my ($class,$struct) = @_;

    my $self = $class->create(
        properties => $struct->{property}
    );
    
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
    my $class = shift;
    my %args = @_;
    
    unless ($args{properties}) { 
        $class->error_message("property list not provided");
        return;
    }

    my $self = $class->SUPER::create(
        input_properties => \@{ $args{properties} },
        output_properties => \@{ $args{properties} },
    );

    return $self;
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
