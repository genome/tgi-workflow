package Workflow::LogLsfUsage;

use strict;
use warnings;

sub write_to_log {
    my $user = getpwuid($<) || 'unknown';
    my $host = Sys::Hostname::hostname();
    my $time = localtime(time);
    my $sub = (caller(1))[3];
    my $message = "$user $host $time $sub \n";
    open (LOGGING, ">>/gscuser/pkimmey/workflow.log");
    print LOGGING $message;
    close (LOGGING);
}

1;
