package Cord::Command::Ns::Internal::End;

use strict;
use warnings;

use Cord ();
use Cord::Command::Ns::Start ();

class Cord::Command::Ns::Internal::End {
    is  => ['Cord::Command'],
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

    $self->status_message(
        sprintf( "Loading workflow instance: %s", $self->instance_id ) );

    my @load = Cord::Operation::Instance->get(
        id => $self->instance_id,
        -recurse => ['parent_instance_id','instance_id']
    );

    my @running = grep {
        my $keep = 0;
        if (!$keep && !$_->can('child_instances')) {
            if($_->status() eq 'running') {
                $keep = 1;
            }
        }
        $keep;
    } @load;

    # TODO
    # if things claim to be running, compare bjobs -g
    # to database list
    # when bad status found
    #  lock row, change status
    #  repeat for parents

    # if actually running
    my $running = scalar @running > 0; #!-e "/gscuser/eclark/stop"; 
    if ( $running ) {

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
            my $done_instance = Cord::Operation::Instance->get(
                $done_instance_id
            );

            my $starter = Cord::Command::Ns::Start->create(
                job_group => $jobgroup
            );

            my $r = $starter->bsub_operation( undef, $done_instance, $done_instance, $jobid );

            $starter->delete;

        }

        exit -80;
    } else {
        # TODO normalize status
        # kill pending jobs if possible
        # exit successfully so user handler runs

        print "noresched $jobid\n";
    }

    print "done\n";

    1;
}

1;
