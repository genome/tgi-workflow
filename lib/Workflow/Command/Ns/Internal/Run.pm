package Workflow::Command::Ns::Internal::Run;

use strict;
use warnings;

use IPC::Open2;
use Storable qw/store_fd fd_retrieve/;

use Workflow ();

class Workflow::Command::Ns::Internal::Run {
    is  => ['Workflow::Command'],
    has => [
        root_instance_id => {
            shell_args_position => 1,
        },
        instance_id => {
            shell_args_position => 2,
            doc                 => 'Instance id to run'
        },
        debug => {
            is => 'Boolean',
            is_optional => 1,
        }
    ]
};

$Workflow::DEBUG_GLOBAL || 0;  ## suppress dumb warnings

sub execute {
    my $self = shift;

    $self->status_message(
        sprintf( "Loading workflow instance: %s", $self->root_instance_id ) );

    my @load = Workflow::Operation::Instance->get(
        id => $self->root_instance_id,
        -recurse => ['parent_instance_id','instance_id']
    );

    $self->status_message(
        sprintf( "Getting operation instance: %s", $self->instance_id ));

    my $opi = Workflow::Operation::Instance->get($self->instance_id);

    $self->status_message(
        sprintf( "Acquiring rowlock on instance: %s", $opi->id));

    my %o_inputs = %{ $opi->input };
    my %r_inputs = $opi->resolved_inputs;

    $self->acquire_rowlock($opi->id);
    $self->status_message("Set status = Running");
    $opi->current->status('running');
    $opi->current->start_time(UR::Time->now);
    UR::Context->commit;

    my $t = $opi->operation->operation_type;

    ## disconnect from workflow database
    Workflow::DataSource::InstanceSchema->disconnect_default_dbh;

    my ($outputs, $exitcode, $ok) = $self->run_optype(
        $t, { %o_inputs, %r_inputs }
    );

    my $status = $ok ? 'done' : 'crashed'; 

    $self->acquire_rowlock($opi->id);
    if ($status eq 'done') {
        $opi->output({ %{ $opi->output }, %{ $outputs }});
    }
    $opi->current->status($status);
    $opi->current->end_time(UR::Time->now);
    UR::Context->commit();

    if ($status eq 'crashed') {

        if ($self->try_count($opi) <= 3) {
            $self->acquire_rowlock($opi->id);
            my $did = $opi->current->dispatch_identifier;
            $opi->reset_current();
            $opi->current->dispatch_identifier($did);
            $opi->current->status('scheduled');
            UR::Context->commit();
            return -88;
        } else {
            return 0;
        }
    }

    if ($status eq 'done' && $opi->name eq 'output connector') {
        $self->acquire_rowlock($opi->parent_instance_id);

        $opi->parent_instance->current->status('done');
        $opi->parent_instance->output({ %{ $opi->input } });

        UR::Context->commit();
    }

    ## set the next things to scheduled
    # TODO this is pretty hard

    1;
}

sub run_optype {
    my ($self, $optype, $inputs) = @_;

    my ($rdr, $wtr);
    my $pid = open2($rdr, $wtr, 'workflow ns internal exec 0 1');

    $self->status_message("Launched runner: $pid");

    my $run = {
        type => $optype,
        input => $inputs
    };

    store_fd($run, $wtr) or die "cant store to subprocess";
    my $out = fd_retrieve($rdr) or die "cant retrieve from subprocess";

    waitpid(-1,0);

    if ($? == -1) {
        $self->error_message("failed to execute $!");
        return $out, $? >>8, 0;
    } elsif ($? & 127) {
        $self->error_message(sprintf("child died with signal %d, %s coredump",
            ($? & 127), ($? & 128) ? 'with' : 'without'));
        return $out, $? >>8, 0;
    } else {
        $self->status_message(sprintf("child exited with value %d", $? >>8));

        return $out, $? >>8, $? >>8 == 0 ? 1 : 0;
    }
}

sub acquire_rowlock {
    my ($self, $instance_id) = @_;

#    die 'todo';

    warn "should lock\n";

    return 1;
}

sub try_count {
    my $self = shift;
    my $op = shift;

    my $dbh = Workflow::DataSource::InstanceSchema->get_default_handle;

    my ($cnt) = $dbh->selectrow_array(<<"    SQL", {}, $op->id);
        SELECT count(workflow_execution_id) FROM workflow.workflow_instance_execution WHERE workflow_instance_id = ?
    SQL

    $self->status_message("Tries so far: $cnt");

    return $cnt;
}

1;
