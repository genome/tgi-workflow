package Workflow::Command::Ns::Internal::End;

use strict;
use warnings;

use Workflow ();
use Workflow::Command::Ns::Start ();

class Workflow::Command::Ns::Internal::End {
    is  => ['Workflow::Command'],
    has => [
        instance_id => {
            shell_args_position => 1,
            doc                 => 'Instance id that had an operation exit'
        },
        done_instance_id => {
            shell_args_position => 2,
            is_optional         => 1
        }
    ]
};

sub execute {
    my $self = shift;

    my $jobid    = $ENV{LSB_JOBID};
    my $jobgroup = $ENV{LSB_JOBGROUP};

    die unless ($jobgroup && $jobgroup ne '');

    unless ($jobid) {
        $self->error_message("command must be run under lsf");
        return;
    }
    if ( !-e "/gscuser/eclark/stop" ) {

        print "resched $jobid\n";

        my ( $sec, $min, $hour, $day, $mon, $year ) =
          localtime( time + 15 * 60 );
        $year += 1900;    ## i hate you perl
        $mon++;

        my $cmd = "bsub -q short -b $year:$mon:$day:$hour:$min -g $jobgroup workflow ns internal end " . $self->instance_id;
        if (my $did = $self->done_instance_id) {
            $cmd .= ' ' . $did;
        }

        $self->status_message('lsf$ ' . $cmd);
        my $bsub_output = `$cmd`;

        $self->status_message($bsub_output);

        if ($?) {
            $self->error_message("couldn't bsub myself");
            return -88;
        }

        my $jobid;
        if ( $bsub_output =~ /^Job <(\d+)> is submitted to queue <(\w+)>\./m ) {
            $jobid = $1;
        } else {
            $self->error_message("cant parse job id from bsub output");
            return -92;
        }

        if (my $done_instance_id = $self->done_instance_id) {
            my $done_instance = Workflow::Operation::Instance->get(
                $done_instance_id
            );

            my $starter = Workflow::Command::Ns::Start->create(
                job_group => $jobgroup
            );

            my $r = $starter->bsub_operation( undef, $done_instance, $done_instance, $jobid );

            $starter->delete;

        }

        exit -80;
    } else {
        print "noresched $jobid\n";
    }

    print "done\n";

    # load workflow
    # find running sub workflows with crashed events
    # if no other event running, set workflow crashed
    # walk upward to parent

    # if things claim to be running, compare bjobs -g
    # to database list
    # when bad status found
    #  lock row, change status

    # if actually running, sleep 30 seconds after all checks are done
    # reload operations that were in running, scheduled or new

    # when nothing else is running but us, kill pending jobs
    # that will never have deps satisfied
    # kill done handler

    # exit successfully so user-defined handler runs

    1;
}

1;
