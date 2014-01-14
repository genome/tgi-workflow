package Workflow::Instrumentation;


# --- WARNING ---
# This is a prototype interface to the statsd server.
# It is likely to change, so use it at your own risk.
# --- WARNING ---


use strict;
use warnings;

use Net::Statsd;
use Time::HiRes;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(decrement
                    increment
                    gauge
                    timer
                    timing
                    );

BEGIN {
    if ($ENV{UR_DBI_NO_COMMIT}) {
        $Net::Statsd::HOST = ''; # disabled if testing
        $Net::Statsd::PORT = 0;

    } else {
        #Not sure if these ENV variables are actually defined in workflow code yet. 
        $Net::Statsd::HOST = $ENV{WORKFLOW_STATSD_HOST} || 'localhost';
        $Net::Statsd::PORT = $ENV{WORKFLOW_STATSD_PORT} || 8125;

    }
};


sub dec {
    eval {
        Net::Statsd::dec(@_);
    };
}

sub decrement {
    eval {
        Net::Statsd::decrement(@_);
    };
}


sub gauge {
    eval {
        Net::Statsd::gauge(@_);
    };
}


sub inc {
    eval {
        Net::Statsd::inc(@_);
    };
}

sub increment {
    eval {
        Net::Statsd::increment(@_);
    };
}


sub timer {
    my ($name, $code) = @_;

    my $start_time = Time::HiRes::time();

    eval {
        $code->();
    };
    if ($@) {
        my $error = $@;
        my $stop_time = Time::HiRes::time();
        eval {
            my $error_name = "$name\_error";
            Net::Statsd::timing($error_name, 1000 * ($stop_time - $start_time));
        };
        die $error;
    }

    my $stop_time = Time::HiRes::time();
    eval {
        Net::Statsd::timing($name, 1000 * ($stop_time - $start_time));
    };
}

sub timing {
    eval {
        Net::Statsd::timing(@_);
    };
}

1;
