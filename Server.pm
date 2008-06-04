
package Workflow::Server;

use strict;
use POE qw(Component::Server::TCP Filter::Reference);
use Workflow;

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

    my $session = POE::Component::Server::TCP->new(
        Alias => 'workflow server',
        Port => 15243,
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
                'send_operation',
                'finish_operation',
                'client_input',
                'client_connect',
                'client_disconnect',
                'run_operation',
                'try_to_execute',
                'finish_workflow'
            ]
        ]
    );

    $self->{workers} = [];
    $self->{worker_op} = {};
    $self->{workflows} = [];
    $self->{wait_for} = {};
    
    $self->{pending_ops} = [];
    
    $self->{session} = $session;
    
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
    my ($self, $opdata, $callback, $edited_input) = @_;
    
    push @{ $self->{pending_ops} }, [$opdata, $callback, $edited_input];
    
#    my $session = $self->{workers}->[0];   
#    my $op = $opdata->operation;
#    $op->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
#    $poe_kernel->post(
#        $session, 'send_operation', $op, $opdata, $edited_input, sub { $callback->($opdata) }
#    );
     
}

### poe single connection events

sub client_connect {
    my ($self, $s) = @_[OBJECT, SESSION];
    print $s->ID . " connect\n";
    
    $self->{wait_for}->{$s->ID} = {};
}

sub client_disconnect {
    my ($self, $s, $k) = @_[OBJECT, SESSION, KERNEL];
    print $s->ID . " disconnect\n";
    
    my @workers = grep { $_ != $s } 
        @{ $self->{workers} };
        
    $self->{workers} = \@workers;
    
    delete $self->{wait_for}->{$s->ID};
    
    if (my $execargs = delete $self->{worker_op}->{$s->ID}) {
        ## something disconnected without finishing its stuff?  Just requeue it at the front.
        
        unshift @{ $self->{pending_ops} }, $execargs;
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
    my ($self, $postback, $s, $k, $h) = @_[OBJECT, ARG0, SESSION, KERNEL, HEAP];
    
    push @{ $self->{workers} }, $s;

    $h->{try_count} = 0;

    $k->yield('try_to_execute');
    
    $postback->(1);
}

sub try_to_execute { 
    my ($self, $s, $k, $h) = @_[OBJECT, SESSION, KERNEL, HEAP];

#    print "trying " . $s->ID . ":" . $h->{try_count} . "\n";

    $h->{try_count}++;
    
    if (my $exec_args = shift @{ $self->{pending_ops} }) {
        $self->{worker_op}->{$s->ID} = $exec_args;
        
        my ($opdata,$callback,$edited_input) = @$exec_args;

        my $op = $opdata->operation;
        $op->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
        $k->yield(
            'send_operation', $op, $opdata, $edited_input, sub { $callback->($opdata) }
        );

        $h->{try_count} = 0;
    } elsif ($h->{try_count} > 5) {
        my $message = Workflow::Server::Message->create(
            type => 'command',
            heap => {
                command => 'hangup',
                args => []
            }
        );

        $h->{client}->put($message);
    } else {
        $k->delay_set('try_to_execute', 5);
    }
}

sub list_workers {
    my ($self, $postback, $s) = @_[OBJECT, ARG0, SESSION];

    my @list = map {
        $_->get_heap->{remote_ip} . ':' . $_->get_heap->{remote_port}
    } @{ $self->{workers} };    
    
    $postback->(@list);
}


sub load_workflow {
    my ($self, $postback, $s, $xml_file) = @_[OBJECT, ARG0, SESSION, ARG1];
    my $workflow = Workflow::Model->create_from_xml($xml_file);
    
    push @{ $self->{workflows} }, $workflow;
    
    $postback->($workflow->id);
}

sub execute_workflow {
    my ($self, $postback, $s, $workflow_id, $inputs) = @_[OBJECT, ARG0, SESSION, ARG2, ARG1];
    my $workflow = Workflow::Model->get($workflow_id);

    my $executor = Workflow::Executor::Server->create;
    $executor->server($self);
    
    $workflow->executor($executor);
    
    my $cb = sub {
        my ($data) = @_;
        warn "callback fired.";
        warn Data::Dumper->new([$data])->Dump;
    };

    my $cb = $s->postback('finish_workflow',$workflow_id);

    my $wfdata = $workflow->execute(
        input => $inputs,
        output_cb => $cb
    );

    $workflow->wait;
    
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
}

sub send_operation {
    my ($self, $op, $opdata, $edited, $callback, $h, $s) = @_[OBJECT, ARG0, ARG1, ARG2, ARG3, HEAP, SESSION];

    my $message = Workflow::Server::Message->create(
        type => 'command',
        heap => {
            command => 'execute',
            args => [ $op->operation_type, %{ $opdata->input }, %{ $edited } ]
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
    $k->yield('try_to_execute');
    
    $callback->($opdata);
}

sub test_response {
    my ($postback) = @_[ARG0];
    
    $postback->('hello world!');
}



1;
