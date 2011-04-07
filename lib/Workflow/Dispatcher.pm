package Workflow::Dispatcher;

use strict;
use warnings;

BEGIN {
    my @dispatchers = [];
    sub dispatchers { return @dispatchers; }
    sub dispatcher_add{ my $dis; push(@dispatchers, $dis); }
}

class Workflow::Dispatcher {
    has => [
        cluster => { is => 'Text' },
        queue => { is => 'Text', default_value => 'long', is_optional => 1 }
    ]
};

sub execute {
    die('Must be implemented in a subclass');
}

sub get_or_create {
    my $class = shift;
    my $engine = shift;
    my $cluster = shift;
    my $queue = shift;
    return "Workflow::Dispatcher::$engine"->create(
        cluster => $cluster,
        queue => $queue
    );
}
