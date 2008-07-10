
package Workflow::Server::Message;

use strict;
use warnings;

class Workflow::Server::Message {
    is_transactional => 0,
    has => [
        type => { is => 'Text' },
        heap => { is => 'HASH' }
    ]
};

sub create {
    my $class = shift;
    my %args = @_;
    
    my $self = $class->SUPER::create;
    
    while (my ($k,$v) = each(%args)) {
        $self->$k($v);
    }

    return $self;
}

1;
