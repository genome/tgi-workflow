package Workflow::Command::Ns::Internal::Run;

use strict;
use warnings;

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

sub execute {
    my $self = shift;

    $self->status_message(
        sprintf( "Loading workflow instance: %s", $self->root_instance_id ) );

    my $wfi = Workflow::Operation::Instance->get(
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

    my $outputs;
    my $status;
    eval {
        local $Workflow::DEBUG_GLOBAL=1 if $self->debug
        $outputs = $t->execute(%o_inputs, %r_inputs);
        $status = 'done'; 
    };
    if ($@) {
        $status = 'crashed';

        $self->error_message($@);
    }

    $self->acquire_rowlock($opi->id);
    if ($status eq 'done') {
        $opi->output({ %{ $opi->output }, %{ $outputs });
    }
    $opi->current->status($status);
    $opi->current->end_time(UR::Time->now);
    UR::Context->commit();

    if ($status eq 'crashed' && $self->try_count($opi) <= 3) {
        $self->acquire_rowlock($opi->id);
        my $did = $opi->current->dispatch_identifier;
        $opi->reset_current();
        $opi->current->dispatch_identifier($did);
        $opi->current->status('scheduled');
        UR::Context->commit();

        return -88;
    }

    if ($status eq 'done' && $opi->name eq 'output connector') {
        $self->acquire_rowlock($opi->parent_instance_id);

        $opi->parent_instance->current->status('done');
        $opi->parent_instance->output(%{ $opi->input });

        UR::Context->commit();
    }

    ## set the next things to scheduled
    # TODO this is pretty hard

    1;
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

    # TODO 

    return 5;
}

1;
