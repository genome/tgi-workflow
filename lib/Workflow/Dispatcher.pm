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
        queue => { is => 'Text', is_optional => 1 }
    ]
};

sub execute {
    die('Must be implemented in a subclass');
}

sub get_or_create {
    my $class = shift;
    my $engine = shift;
    my $cluster = shift;
    print $engine;
    return "Workflow::Dispatcher::$engine"->create(
        engine => $engine,
        cluster => $cluster
    );
}
