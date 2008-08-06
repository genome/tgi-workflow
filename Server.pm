
package Workflow::Server;

use strict;

use POE qw(Component::Server::TCP Filter::Reference);
use Sys::Hostname;
use Workflow ();

our $server_singleton;

sub new {
    my $class = shift;
    
    return $server_singleton || bless({},$class);
}

sub run {
    my $class = shift;
    unless (ref($class)) {
        my $self = $class->create;
    }

    POE::Kernel->run();
    exit;
}

sub create {
    my $class = shift;
    my $self = $class->new();
    $server_singleton = $self;

    my %args = @_;

    my $namespace = $args{namespace} || 'Workflow';
    my @inc;
    if ($args{inc}) {
        @inc = @{ $args{inc} };
    } else {
        @inc = ();
    }

    my $server_host = hostname;
    my $server_port = 15243;

    if ($args{server_port}) {
        $server_port = delete $args{server_port};
    }

    my $incstr = '';
    foreach my $inc (@inc) {
        $incstr .= ' use lib "' . $inc .'";';
    }

    $Storable::forgive_me = 1;

    my $session = POE::Component::Server::TCP->new(
        Alias => 'workflow server',
        Port => $server_port,
        ClientFilter => 'POE::Filter::Reference',
        ClientInput => \&_client_input,
        ClientConnected => \&_client_connect,
        ClientDisconnected => \&_client_disconnect,
        ObjectStates => [
            $self => [ 
                'send_command_result',
                'test_response',
                'announce_worker', 
                'list_workers',
                'load_workflow',
                'execute_workflow',
                'resume_workflow',
                'send_operation',
                'finish_operation',
                'client_input',
                'client_connect',
                'client_disconnect',
                'run_operation',
                'try_to_execute',
                'finish_workflow',
                'hangup'
            ]
        ]
    );

    $self->{workers} = [];
    $self->{worker_op} = {};
    $self->{workflows} = [];
    $self->{wait_for} = {};

    $self->{executions} = {};
    
    $self->{pending_ops} = [];
    
    $self->{session} = $session;
   
    $self->{namespace} = $namespace;
    $self->{server_host} = $server_host;
    $self->{server_port} = $server_port;
    $self->{include_string} = $incstr;

    return $self;
}

### pure perl functions, poe calls them

sub _client_connect {
    $poe_kernel->call($_[SESSION], 'client_connect', @_[ARG0..$#_]);
}

sub _client_disconnect {
    $poe_kernel->call($_[SESSION], 'client_disconnect', @_[ARG0..$#_]);
}

sub _client_input {    
    $poe_kernel->call($_[SESSION], 'client_input', @_[ARG0..$#_]);
}

### server object methods

sub run_operation {
    my ($self, $opdata, $edited_input) = @_;
    
    push @{ $self->{pending_ops} }, [$opdata, $edited_input];
    
    unless ($opdata->operation->operation_type->can('executor') && defined $opdata->operation->operation_type->executor) {

        $opdata->status_message('bsub: ' . $opdata->operation->name);
        $self->start_new_worker($opdata);  ## start a blade job if it doesnt have an exception
    }
}

sub start_new_worker {
    my ($self,$operation_instance) = @_;
    
    my $rusage = ' ';
    my $queue = 'short';
    my $optype = $operation_instance->operation->operation_type;
    if ($optype->can('lsf_resource') && defined $optype->lsf_resource) {
        $rusage = ' -R "' . $optype->lsf_resource . '"';
    }
    if ($optype->can('lsf_queue') && defined $optype->lsf_queue) {
        $queue = $optype->lsf_queue;
    }
    
    my $client_start_cmd = 'bsub -q ' . $queue . ' -N -u "eclark@genome.wustl.edu"' . $rusage .
        'perl -e \'BEGIN { delete $ENV{PERL_USED_ABOVE}; }' . $self->{include_string} . ' use above "' . $self->{namespace} . 
        '"; use Workflow::Client; Workflow::Client->run_worker("' .
        $self->{server_host} . '",' . $self->{server_port} . ',"' . $operation_instance->id . '")\'';
 
    system($client_start_cmd);
}

### poe single connection events

sub client_connect {
    my ($self, $s) = @_[OBJECT, SESSION];
#    print $s->ID . " connect\n";
    
    $self->{wait_for}->{$s->ID} = {};
}

sub client_disconnect {
    my ($self, $s, $k) = @_[OBJECT, SESSION, KERNEL];
#    print $s->ID . " disconnect\n";
    
    my @workers = grep { $_ != $s } 
        @{ $self->{workers} };
        
    $self->{workers} = \@workers;
    
    delete $self->{wait_for}->{$s->ID};
    
    if (my $execargs = delete $self->{worker_op}->{$s->ID}) {
        ## something disconnected without finishing its stuff?  Just requeue it at the front.
        
        unshift @{ $self->{pending_ops} }, $execargs;
        $self->start_new_worker($execargs->[0]);
    }
    
    $k->alarm_remove_all;
}

sub client_input {
    my ($input,$k,$s,$h,$self) = @_[ARG0, KERNEL, SESSION, HEAP, OBJECT];

#    print Data::Dumper->new([$input])->Dump;
    if ($input->type eq 'response') {
        if ($input->heap->{original_message_id} &&
            $self->{wait_for}->{$s->ID}->{ $input->heap->{original_message_id} }) {

            my $sub = $self->{wait_for}->{$s->ID}->{ $input->heap->{original_message_id} };
            delete $self->{wait_for}->{$s->ID}->{ $input->heap->{original_message_id} };
            if (ref($sub) && ref($sub) eq 'POE::Session::AnonEvent') {
                $sub->($input);
            }
        } else {
            warn 'unusual response';
            print STDERR Data::Dumper->new([$self->{wait_for}->{$s->ID}])->Dump;
        }
    } elsif ($input->type eq 'command') {
        my $cb = $s->postback('send_command_result', $input);

        $k->yield(
            $input->heap->{command},
            $cb,
            @{ $input->heap->{args} }
        );
    }
}

sub send_command_result {
    my ($self, $creation_args, $called_args, $h) = @_[OBJECT, ARG0, ARG1, HEAP];
    
    my $message = Workflow::Server::Message->create(
        type => 'response',
        heap => {
            original_message_id => $creation_args->[0]->id,
            result => $called_args
        }
    );
    
    $h->{client}->put($message);
}

sub announce_worker {
    my ($self, $postback, $operation_instance_id, $s, $k, $h) = @_[OBJECT, ARG0, ARG1, SESSION, KERNEL, HEAP];
    
    unless ($operation_instance_id) {
        $postback->(0);
        $k->yield('hangup');
        
        return;
    }
    
    push @{ $self->{workers} }, $s;
    $self->{worker_op}->{$s->ID} = [Workflow::Operation::Instance->get($operation_instance_id)];

    $h->{try_count} = 0;

    $k->yield('try_to_execute');
    
    $postback->(1);
}

sub try_to_execute { 
    my ($self, $s, $k, $h) = @_[OBJECT, SESSION, KERNEL, HEAP];

#    print "trying " . $s->ID . ":" . $h->{try_count} . "\n";

    $h->{try_count}++;
    
    if ($self->{pending_ops}->[0]->[0]->id eq $self->{worker_op}->{$s->ID}->[0]->id) {
        my $exec_args = shift @{ $self->{pending_ops} };
        my ($opdata,$edited_input) = @$exec_args;

        $self->{worker_op}->{$s->ID} = $exec_args;

        my $op = $opdata->operation;
#        $op->status_message('exec/' . $opdata->model_instance->id . '/' . $op->name);
        $k->yield(
            'send_operation', $op, $opdata, $edited_input, sub { $opdata->completion; }
        );

        $h->{try_count} = 0;
    } elsif ($h->{try_count} > 50) {
        $k->yield('hangup');
    } else {
        $k->delay_set('try_to_execute', 5);
    }
}

sub hangup {
    my ($self, $s, $k, $h) = @_[OBJECT, SESSION, KERNEL, HEAP];

    my $message = Workflow::Server::Message->create(
        type => 'command',
        heap => {
            command => 'hangup',
            args => []
        }
    );

    $h->{client}->put($message);
}

sub list_workers {
    my ($self, $postback, $s) = @_[OBJECT, ARG0, SESSION];

    my @list = map {
        $_->get_heap->{remote_ip} . ':' . $_->get_heap->{remote_port}
    } @{ $self->{workers} };    
    
    $postback->(@list);
}

sub list_instances {
    my ($self, $postback, $s) = @_[OBJECT, ARG0, SESSION];

    my @list = values %{ $self->{executions} };
    
    $postback->(@list);
}

sub load_workflow {
    my ($self, $postback, $s, $xml_file) = @_[OBJECT, ARG0, SESSION, ARG1];
    my $workflow = Workflow::Model->create_from_xml($xml_file);
    
    push @{ $self->{workflows} }, $workflow;
    
    $postback->($workflow->id);
}

sub resume_workflow {
    my ($self, $postback, $s, $workflow_id, $saved_id) = @_[OBJECT, ARG0, SESSION, ARG2, ARG1];
    my $workflow = Workflow::Model->get($workflow_id);

    my $executor = Workflow::Executor::Server->create;
    $executor->server($self);
    $workflow->set_all_executor($executor);
    
    my $model_saved_instance = Workflow::Model::SavedInstance->get($saved_id);
    my $model_instance = $model_saved_instance->load_instance($workflow);
 
    my $cb = $s->callback('finish_workflow',$workflow_id);
    $model_instance->output_cb($cb);

    my $wfdata = $model_instance->resume_execution;

    $workflow->wait;
    
    $postback->($wfdata);
}

sub execute_workflow {
    my ($self, $postback, $s, $workflow_id, $inputs) = @_[OBJECT, ARG0, SESSION, ARG2, ARG1];
    my $workflow = Workflow::Model->get($workflow_id);

    my $executor = Workflow::Executor::Server->create;
    $executor->server($self);
    $workflow->set_all_executor($executor);
 
    my $store = Workflow::Store::Db->create;
 
    my $cb = $s->callback('finish_workflow',$workflow_id);
    my $wfdata = $workflow->execute(
        input => $inputs,
        output_cb => $cb,
        store => $store
    );

    $workflow->wait;

    $self->{executions}->{$wfdata->id} = $wfdata;
    
    $postback->($wfdata);
}

sub finish_workflow {
    my ($self, $creation_args, $called_args, $s, $k, $h) = @_[OBJECT, ARG0, ARG1, SESSION, KERNEL, HEAP];
    my $workflow_id = $creation_args->[0];
    my $data = $called_args->[0];
 
    if (defined $h->{client}) {
    
        my $message = Workflow::Server::Message->create(
            type => 'command',
            heap => {
                command => 'workflow_finished',
                args => [ $workflow_id, $data ]
            }
        );    

        $self->{wait_for}->{$s->ID}->{$message->id} = 1;
        $h->{client}->put($message);
    }
    
    delete $self->{executions}->{$data->id};
}

sub send_operation {
    my ($self, $op, $opdata, $edited, $callback, $h, $s) = @_[OBJECT, ARG0, ARG1, ARG2, ARG3, HEAP, SESSION];

#
#   build a list of modules to use here and send them

    my @list = ();
    foreach my $op ($op->workflow_model->operations) {
        if ($op->operation_type->isa('Workflow::OperationType::Command')) {
            my $command_class = $op->operation_type->command_class_name;
            
            push @list, $command_class;
        }
    }

    my $message = Workflow::Server::Message->create(
        type => 'command',
        heap => {
            command => 'execute',
            args => [ \@list, $op->operation_type, %{ $opdata->input }, %{ $edited } ]
        }
    );

    $self->{wait_for}->{$s->ID}->{$message->id} = $s->postback('finish_operation',$callback,$opdata);
    $h->{client}->put($message);

}

sub finish_operation {
    my ($self, $creation_args, $called_args, $s, $k) = @_[OBJECT, ARG0, ARG1, SESSION, KERNEL];
    my $callback = $creation_args->[0];
    my $opdata = $creation_args->[1];
    my $message = $called_args->[0];

    $opdata->output({ %{ $opdata->output }, @{ $message->heap->{result} } });
    $opdata->is_done(1);

    delete $self->{worker_op}->{$s->ID};
    $k->yield('hangup');
    
    $callback->($opdata);
}

sub test_response {
    my ($postback) = @_[ARG0];
    
    $postback->('hello world!');
}



1;
