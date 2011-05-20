# This is not currently used.
# Ideally it should remove the need
# for special fork related code in Hub.pm.

use strict;
use warnings;

class Workflow::Dispatcher::Fork {
    is => 'Workflow::Dispatcher',
};

sub execute {
    my $self = shift;
    my $job = shift;
    my $pid;
    {
        if ($pid = fork()) {
            # parent
            return 'P' . $pid;
        } elsif (defined $pid) {
            open STDOUT, '>>', $job->stdout if (defined $job->stdout);
            open STDERR, '>>', $job->stderr if (defined $job->stderr);
            my $cmd = $job->command;
            `$cmd`;
        }
    }
}
