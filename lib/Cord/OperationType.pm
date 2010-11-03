
package Cord::OperationType;

use strict;
use warnings;
use Carp;

class Cord::OperationType {
    is_abstract => 1,
    has => [
        stay_in_process => { 
            is => 'Boolean',
            is_optional => 1,
            is_class_wide => 1,
            is_constant => 1,
            is_abstract => 1,
            doc => 'Forces serial executor'
        },
        input_properties => { 
            is => 'ARRAY', 
            doc => 'list of all input properties',
            value => []
        },
        optional_input_properties => {
            is => 'ARRAY',
            doc => 'list of optional input properties',
            value => []
        },
        output_properties => { 
            is => 'ARRAY', 
            doc => 'list of output properties',
            value => [] 
        }
    ]
};

sub create_from_xml_simple_structure {
    my ($my_class, $struct) = @_;

    # delegate to the right one

    my $self;
    if (ref($struct) =~ /ARRAY/) {
        Carp::confess 'xml for operationtype parsed into array. possible multiple operationtype elements in document'; 
    }

    my $class = delete $struct->{typeClass};
    if (defined $class && $class->class && $my_class ne $class && $class->can('create_from_xml_simple_structure')) {

        $self = $class->create_from_xml_simple_structure($struct);

        unless ($self->input_properties) {
            $self->input_properties($struct->{inputproperty});
        }
        unless ($self->output_properties) {
            $self->output_properties([@{$struct->{outputproperty}},'result']);
        }
        unless ($self->optional_input_properties) {
            $self->optional_input_properties([]);
        }
    } else {

        my $input_property = $struct->{inputproperty};
        my $optional_input_property = [];

        if ($input_property) {
            my $new_input_property = [];
            foreach my $prop (@{ $input_property }) {
                if (ref($prop) eq 'HASH') {
                    push @{ $new_input_property }, $prop->{content};
                    if (defined($prop->{isOptional}) && $prop->{isOptional} ne lc('n') && $prop->{isOptional} ne lc('f')) {
                        push @{ $optional_input_property }, $prop->{content};
                    }
                } else {
                    push @{ $new_input_property }, $prop;
                }
            }
            $input_property = $new_input_property;
        }


        $self = $my_class->create(
            input_properties => $input_property,
            output_properties => $struct->{outputproperty},
            optional_input_properties => $optional_input_property
        );
    }

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {};

    if (ref($self) ne __PACKAGE__) {
        $struct->{typeClass} = ref($self);
    }

    my $inputproperty = [];
    foreach my $prop (@{ $self->input_properties }) {
        if (grep { $_ eq $prop } @{ $self->optional_input_properties }) {
            push @$inputproperty, { content => $prop, isOptional => 'Y'};
        } else {
            push @$inputproperty, $prop;
        }
    }

    $struct->{inputproperty} = $inputproperty;
    $struct->{outputproperty} = $self->output_properties;

    return $struct;
}

# successful noop by default, should be overridden
sub execute {

    {};
}

1;
