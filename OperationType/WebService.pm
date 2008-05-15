
package Workflow::OperationType::WebService;

use strict;
use warnings;

class Workflow::OperationType::WebService {
    isa => 'Workflow::OperationType',
    has => [
        wsdl_url => { is => 'String' },
        wsdl_operation => { is => 'String' },
    ],
};

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{commandClass} = $self->command_class_name;

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub create_from_url {

}

sub execute {

}

1;
