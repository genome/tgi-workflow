
package Workflow::OperationType::Command;

use strict;
use warnings;

class Workflow::OperationType::Command {
    isa => 'Workflow::OperationType',
    has => [
        command_class_name => { is => 'String' },
    ],
};

sub create_from_xml_simple_structure {
    my ($class, $struct) = @_;

    my $command = delete $struct->{commandClass};

    eval "use $command"; 
    if ($@) {
        die $@;
    }

    my $self = $command->operation;
 
    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{commandClass} = $self->command_class_name;

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub create_from_command {
    my ($self, $command_class, $options) = @_;

    unless ($command_class->get_class_object) {
        die 'invalid command class';
    }

    unless ($options->{input} && $options->{output}) {
        die 'invalid input/output definition';
    }

    my @valid_inputs = grep {
        $self->_validate_property( $command_class, input => $_ )
    } @{ $options->{input} };

    my @valid_outputs = grep {
        $self->_validate_property( $command_class, output => $_ )
    } @{ $options->{output} }, 'result';

    return $self->create(
        input_properties => \@valid_inputs,
        output_properties => \@valid_outputs,
        command_class_name => $command_class,
    );
}

sub _validate_property {
    my ($self, $class, $direction, $name) = @_;

    my $meta = $class->get_class_object->get_property_meta_by_name($name);

    if (($direction ne 'output' && $meta->property_name eq 'result') ||
        ($direction ne 'output' && $meta->is_calculated)) {
        return 0;
    } else {
        return 1;
    }
}

# delegate to wrapped command class
sub execute {
    my $self = shift;
    my %properties = @_;

    my $command_name = $self->command_class_name;

    my $command = $command_name->create(
        %properties
    );

    my $retvalue = $command->execute;

    my %outputs = ();
    foreach my $output_property (@{ $self->output_properties }) {
        $outputs{$output_property} = $command->$output_property;
    }

    return \%outputs;
}

1;
