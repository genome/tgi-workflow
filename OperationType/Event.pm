
package Workflow::OperationType::Event;

use strict;
use warnings;

class Workflow::OperationType::Event {
    isa => 'Workflow::OperationType',
    is_transactional => 0,
    id_by => [ 'event_id' ],
    has => [
        event_id => { is => 'String' },
        command_class_name => { is => 'String', value => 'Genome::Model::Event' },
        lsf_resource => { is => 'String', is_optional=>1 },
        lsf_queue => { is => 'String', is_optional=>1 },
    ],
};

sub get {
    my $class = shift;
    return $class->SUPER::get( @_ ) || $class->create ( @_ );
}

sub create {
    my $class = shift;
    my $params = $class->preprocess_params(@_);
    
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

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{eventId} = $self->event_id;
    
    $struct->{lsfResource} = $self->lsf_resource if ($self->lsf_resource);
    $struct->{lsfQueue} = $self->lsf_queue if($self->lsf_queue);

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

# delegate to wrapped command class
sub execute {
    my $self = shift;
    my %properties = @_;

    umask 0022;

$DB::single = $DB::stopper;
    # Give the add-reads top level step a chance to sync database so these events
    # show up
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

    unless ($event->verify_prior_event) {
        my $prior_event =  $event->prior_event;
        $self->error_message('Prior event did not verify: '. $prior_event->genome_model_event_id .' '.
        $prior_event->event_status);
        $event->date_completed(undef);
        $event->event_status('Failed');
        $event->user_name($ENV{'USER'});
        return;
    }

#    unless ($event->model_id == $self->model_id) {
#        $self->error_message("The model id for the loaded event ".$event->model_id.
#                             " does not match the command line ".$self->model_id);
#        return;
#    }
    
    my $command_obj = $event;
    $command_obj->revert;

#    unless ($command_obj->lsf_job_id) {
        $command_obj->lsf_job_id($ENV{'LSB_JOBID'});
#    }
    $command_obj->date_scheduled(UR::Time->now());
    $command_obj->date_completed(undef);
    $command_obj->event_status('Running');
    $command_obj->user_name($ENV{'USER'});

    UR::Context->commit();

#    if ($Workflow::DEBUG_GLOBAL) {
#        if (UNIVERSAL::can('Devel::ptkdb','brkonsub')) {
#            Devel::ptkdb::brkonsub($command_name . '::execute');
#        } elsif (UNIVERSAL::can('DB','cmd_b_sub')) {
#            DB::cmd_b_sub($command_name . '::execute');
#        } else {
#            $DB::single=2;
#        }
#    }


    my $rethrow;

    my $rv;
    eval { $rv = $command_obj->execute(); };

    $command_obj->date_completed(UR::Time->now());
    if ($@) {
        $self->error_message($@);
        $command_obj->event_status('Crashed');
        $rethrow = $@;
    } elsif($rv <= 1) {
        $command_obj->event_status($rv ? 'Succeeded' : 'Failed');
    }elsif($rv == 2) {
        $command_obj->event_status('Waiting');
    }
    else {
        $self->status_message("Unhandled positive return code: $rv...setting Succeeded");
        $command_obj->event_status('Succeeded');
    }

    UR::Context->commit();

    die $rethrow if defined $rethrow;

    return unless $command_obj->event_status('Succeeded');
    return { result => $rv };
}

1;
