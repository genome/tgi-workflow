package Workflow::Command::Ns::Internal::Run;

use strict;
use warnings;

use AnyEvent::Util;
use IPC::Run qw(start);
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

    $self->status_message("Operation finished: $status");

    $self->acquire_rowlock($opi->id);
    if ($status eq 'done') {
        $opi->output({ %{ $opi->output }, %{ $outputs }});
    }
    $opi->current->status($status);
    $opi->current->end_time(UR::Time->now);
    UR::Context->commit();

    if ($status eq 'crashed') {
        my $cnt = $self->try_count($opi);

        if ($cnt <= 3) {
            $self->status_message("Resetting for try " . $cnt + 1);

            $self->acquire_rowlock($opi->id);
            my $did = $opi->current->dispatch_identifier;
            $opi->reset_current();
            $opi->current->dispatch_identifier($did);
            $opi->current->status('scheduled');
            UR::Context->commit();
            return -88;
        } else {
            $self->status_message("Aborting, too many tries: " . $cnt);
            return 0;
        }
    }

    ## fix stuff so this isnt necessary

    if ($status eq 'done' && $opi->name eq 'input connector') {
        $self->acquire_rowlock($opi->id);
        $opi->output({ %{ $opi->parent_instance->input() } });
        UR::Context->commit();
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

    my $run = {
        type => $optype,
        input => $inputs
    };

    my $wtr = IO::Handle->new;
    my $rdr = IO::Handle->new;
    $wtr->autoflush(1);
    $rdr->autoflush(1);

    my @cmd = qw(workflow ns internal exec /dev/fd/3 /dev/fd/4);

    my $h = start \@cmd,
        '3<pipe' => $wtr,
        '4>pipe' => $rdr;

    store_fd($run, $wtr) or die "cant store to subprocess";

    $h->pump;
    my $out = fd_retrieve($rdr) or die "cant retrieve from subprocess";

    $h->pump;

    unless ($h->finish) {
        $? = $h->full_result;

        if ($? == -1) {
            $self->error_message("failed to execute $!");
            return $out, $? >>8, 0;
        } elsif ($? & 127) {
            $self->error_message(sprintf("child died with signal %d, %s coredump",
                ($? & 127), ($? & 128) ? 'with' : 'without'));
            return $out, $? >>8, 0;
        } else {
            $self->status_message(sprintf("child exited with value %d", $? >>8));

            return $out, $? >>8, 0;
        }
    }

    return $out, 0, 1;
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

    return $cnt;
}

1;
