
package Workflow::OperationType::Event;

use strict;
use warnings;
use Sys::Hostname;

class Workflow::OperationType::Event {
    isa => 'Workflow::OperationType',
    is_transactional => 0,
    id_by => [ 'event_id' ],
    has => [
        event_id => { is => 'String' },
        command_class_name => { is => 'String', value => 'Genome::Model::Event' },
        lsf_resource => { is => 'String', is_optional=>1 },
        lsf_queue => { is => 'String', is_optional=>1 },
        lsf_project => { is => 'String', is_optional=>1 },
    ],
};

sub get {
    my $class = shift;
    return $class->SUPER::get( @_ ) || $class->create ( @_ );
}

sub create {
    my $class = shift;
    my $params = { $class->define_boolexpr(@_)->normalize->params_list };

    die 'missing command class' unless $params->{event_id};

    my $self = $class->SUPER::create(@_);

    $self->input_properties(['prior_result']);
    $self->output_properties(['result']);    

    return $self;
}

sub create_from_xml_simple_structure {
    my ($class, $struct) = @_;

    my $id = delete $struct->{eventId};
    my $self = $class->get($id);

    $self->lsf_resource(delete $struct->{lsfResource}) if (exists $struct->{lsfResource});
    $self->lsf_queue(delete $struct->{lsfQueue}) if (exists $struct->{lsfQueue});
    $self->lsf_project(delete $struct->{lsfProject}) if (exists $struct->{lsfProject});

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{eventId} = $self->event_id;

    $struct->{lsfResource} = $self->lsf_resource if ($self->lsf_resource);
    $struct->{lsfQueue} = $self->lsf_queue if($self->lsf_queue);
    $struct->{lsfProject} = $self->lsf_project if($self->lsf_project);

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub stdout_log {
    my $self = shift;
    if (my $res = $self->lsf_resource) {
        if ($res =~ /-o (.+?) -e/) {
            return $1;
        }
    }   
    return;
}

sub stderr_log {
    my $self = shift;
    if (my $res = $self->lsf_resource) {
        if ($res =~ /-e (.+?)$/) {
            return $1;
        }
    }
    return;
}

sub shortcut {
    my $self = shift;
    $self->call('shortcut', @_);
}

sub execute {
    my $self = shift;
    $self->call('execute', @_);
}

# delegate to wrapped command class
sub call {
    my $self = shift;
    my $type = shift;

    unless ($type eq 'shortcut' || $type eq 'execute') {
        die 'invalid type: ' . $type;
    }
    my %properties = @_;

    require Genome;

    #umask 0022;

    # Give the add-reads top level step a chance to 
    # sync database so these events show up
    my $try_count = 10;
    my $event;
    while($try_count--) {
        $event = Genome::Model::Event->load(id => $self->event_id);
        last if ($event);
        sleep 5;
    }
    unless ($event) {
        $self->error_message('No event found with id '.$self->event_id);
        die 'no event found';
    }
    if ($event->event_status and $event->event_status =~ /Succeeded|Abandoned/) {
        $self->error_message("Shortcutting event with status ".$event->event_status);
        return { result => 1 };
    }

    my $command_name = ref($event);

    if ($type eq 'shortcut' && !$command_name->can('_shortcut_body')) {
        return;
    }

    $command_name->dump_status_messages(1);
    $command_name->dump_warning_messages(1);
    $command_name->dump_error_messages(1);
    $command_name->dump_debug_messages(0);

    unless ($event->verify_prior_event) {
        my $prior_event =  $event->prior_event;
        $self->error_message('Prior event did not verify: '. $prior_event->genome_model_event_id .' '.
        $prior_event->event_status);
        $event->date_completed(undef);
        $event->event_status('Failed');
        $event->user_name($ENV{'USER'});
        # should this return nothing?  in the shortcut case its just going
        # to reschedule the process on lsf (and probably fail again)
        return;
    }

    my $command_obj = $event;
    $command_obj->revert;

    $command_obj->lsf_job_id($ENV{'LSB_JOBID'});
    $command_obj->date_scheduled(Workflow::Time->now());
    $command_obj->date_completed(undef);
    $command_obj->event_status('Running');
    $command_obj->user_name($ENV{'USER'});

    UR::Context->commit();

    $self->status_message('#################################################');
    $self->status_message('Date Scheduled:  '. $command_obj->date_scheduled);
    $self->status_message('Type:  ' . $type);
    if (defined $command_obj->lsf_job_id) {
        $self->status_message('LSF Job Id:  '. $command_obj->lsf_job_id);
    }
    $self->status_message('Pid:  ' . $$);
    $self->status_message('HOST:  '. hostname);
    $self->status_message('USER:  '. $command_obj->user_name);

    if ($Workflow::DEBUG_GLOBAL) {
        if (UNIVERSAL::can('Devel::ptkdb','brkonsub')) {
            Devel::ptkdb::brkonsub($command_name . '::execute');
        } elsif (UNIVERSAL::can('DB','cmd_b_sub')) {
            DB::cmd_b_sub($command_name . '::execute');
        } else {
            $DB::single=2;
        }
    }

    my $rethrow;

    my $rv;
    eval { 
        local $ENV{UR_STACK_DUMP_ON_DIE} = 1;

        if ($type eq 'shortcut') {
            unless ($command_obj->can('shortcut')) {
                die ref($command_obj) . ' has no method shortcut; ' .
                    'dying so execute can run on another host';
            }
            $rv = $command_obj->shortcut();
        } elsif ($type eq 'execute') {
            $rv = $command_obj->execute();
        }
    };

    if ($@) {
        $self->error_message($@);
        $rethrow = $@;
        UR::Context->rollback();
        $command_obj->event_status('Crashed');

    } elsif(!defined $rv || !$rv) {
        $command_obj->event_status('Failed');
    } elsif($rv <= 1) {
        $command_obj->event_status('Succeeded');
    }elsif($rv == 2) {
        $command_obj->event_status('Waiting');
    }
    else {
        $self->status_message("Unhandled positive return code: $rv...setting Succeeded");
        $command_obj->event_status('Succeeded');
    }

    $command_obj->date_completed(Workflow::Time->now());


    my $commit_rv;
    eval {
        $commit_rv = UR::Context->commit();
    };
    if ($@ || !$commit_rv) {
        if ($rethrow) {
            $rethrow .= "\n Failed to commit: " . $@;
        } else {
            $rethrow = $@;
        }

        eval {
            UR::Context->rollback();
        };
    
        if ($@) {
            $rethrow .= "\n Plus this error from attempting to rollback: " . $@;
        }

        $command_obj->event_status('Failed');
        $command_obj->date_completed(Workflow::Time->now());
        UR::Context->commit();
    }

    die $rethrow if defined $rethrow;

    return unless ($command_obj->event_status eq 'Succeeded');
    return { result => $rv };
}

sub resource {
    my $self = shift;
    return Workflow::LsfParser->get_resource_from_lsf_resource($self->lsf_resource);
}

1;
