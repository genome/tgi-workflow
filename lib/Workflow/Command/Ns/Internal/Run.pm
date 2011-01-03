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
            doc => ''
        },
        xauth => {
            is_optional => 1,
            doc => 'token to add to xauth to enable ptkdb'
        }
    ]
};

sub execute {
    my $self = shift;

    my $xauth = $self->xauth;
    if (defined $xauth) {
        $self->status_message("Adding xauth token");

        return unless ($self->_xauth("add", " . $xauth"));
    }

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

    $self->acquire_rowlock($opi->id);
    $self->status_message("Set status = Running");
    $opi->current->status('running');
    $opi->current->start_time(UR::Time->now);
    UR::Context->commit;

    my $t = $opi->operation->operation_type;

    ## disconnect from workflow database
    Workflow::DataSource::InstanceSchema->disconnect_default_dbh;

    my ($outputs, $exitcode, $ok) = $self->run_optype(
        $t, $self->merged_input($opi) 
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
            $self->status_message("Resetting for try " . ($cnt + 1));

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
        $opi->output($self->merged_input($opi->parent_instance));
        UR::Context->commit();
    }

    if ($status eq 'done' && $opi->name eq 'output connector') {
        $self->acquire_rowlock($opi->parent_instance_id);

        $opi->parent_instance->current->status('done');
        $opi->parent_instance->output($self->merged_input($opi));

        UR::Context->commit();
    }

    # TODO set the next things to scheduled

    # TODO capture runtime stats from bjobs/rusage struct

    if (defined $xauth) {
        $self->status_message("Removing xauth token");

        unless ($self->_xauth("remove")) {
            $self->warning_message("Failed to remove xauth token, proceeding anyway");
        }
    }

    1;
}

sub merged_input {
    my $self = shift;
    my $opi = shift;

    my %o_inputs = %{ $opi->input };
    my %r_inputs = $opi->resolved_inputs;

    return { %o_inputs, %r_inputs }
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

    if ($self->debug) {
        require File::Which;
        my $workflow_cmd = File::Which::which('workflow');

        unless ($? == 0) {
            $self->error_message("Failed command: $workflow_cmd");
            return {},0,0;
        }

        chomp($workflow_cmd);

        $cmd[0] = $workflow_cmd;
       
        splice(@cmd,4,0,'--debug');
 
        unshift @cmd, $^X, '-d:ptkdb';
    }

    $self->status_message("Executing: " . join(' ', @cmd));

    my $h = start \@cmd,
        '3<pipe' => $wtr,
        '4>pipe' => $rdr;

    store_fd($run, $wtr) or die "cant store to subprocess";

    my $out;
    if ($h->pumpable) {
        $h->pump;
        eval {
            $out = fd_retrieve($rdr) or die "fd_retrieve failed: $!";
        };
        if ($@) {
            $self->error_message("Failed to retrieve output\n$@");
        }
    }

    $h->pump if $h->pumpable;

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

    if (!defined $out) {
        $self->warning_message("Command exited without errors, but output hash is indefined");
        return $out, 0,0;
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

sub _xauth {
    my ($self, $cmd, $arg) = @_;

    $arg ||= '';

    $cmd = 'xauth -q ' . $cmd . ' $DISPLAY' . $arg;

    system($cmd);
    if ($? == -1) {
        $self->error_message("Couldnt run xauth");
        return;
    } elsif ($? & 127) {
        $self->error_message(sprintf("xauth died with signal %d, %s coredump",
            ($? & 127), ($? & 128) ? 'with' : 'without'));
        return;
    } elsif ($? << 8) {
        $self->error_message("Xauth exited with code: " . $? << 8);
        return;
    }

    1;
}

1;
