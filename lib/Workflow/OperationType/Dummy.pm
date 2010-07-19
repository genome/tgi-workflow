
package Workflow::OperationType::Dummy;

use strict;
use warnings;

class Workflow::OperationType::Dummy {
    isa => 'Workflow::OperationType',
};

sub execute {
    my $self = shift;
    my %properties = @_;

    return {};
}

1;
