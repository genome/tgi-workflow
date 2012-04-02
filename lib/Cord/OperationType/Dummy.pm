
package Cord::OperationType::Dummy;

use strict;
use warnings;

class Cord::OperationType::Dummy {
    isa => 'Cord::OperationType',
};

sub execute {
    my $self = shift;
    my %properties = @_;

    return {};
}

1;
