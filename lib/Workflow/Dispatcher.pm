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
        cluster => { is => 'Text', is_optional => 1 },
        default_queue => { is => 'Text', is_optional => 1 }
    ]
};

sub execute {
    die('Must be implemented in a subclass');
}

# call each dispatchers can_run method
sub get_class {
    if (defined $ENV{'WF_DISPATCHER'}) {
        if ($ENV{'WF_DISPATCHER'} eq "lsf") {
            return "Workflow::Dispatcher::Lsf";
        } elsif ($ENV{'WF_DISPATCHER'} eq "sge") {
            return "Workflow::Dispatcher::Sge";
        } elsif ($ENV{'WF_DISPATCHER'} eq 'fork') {
            return "Workflow::Dispatcher::Fork";
        }
    }
    if (`which bsub` && `which bhosts` && `which bjobs`) {
        return "Workflow::Dispatcher::Lsf";
    } elsif (`which qsub` && `which qhost` && `which qstat`) {
        return "Workflow::Dispatcher::Sge";
    }
}

# Retrieve an instance of Dispatcher::(subclass)
# based either on supplied args or on what dispatchers
# are available on the current machine.
sub get {
    my $cls = shift;
    if (!defined $cls) {
        die("Dispatcher->get must be called as method not function");
    }
    my $engine = shift;
    my $cluster = shift;
    my $queue = shift;
    my $subcls = $cls->get_class;
    return $subcls->create();
}
