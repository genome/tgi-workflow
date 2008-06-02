
package Workflow::Server;

use strict;
use POE qw(Component::Server::TCP Filter::Reference);
use Workflow;

our $server_singleton;

sub new {
    my $class = shift;
    
    return bless({},$class);
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
        ClientInput => \&_client_input_stub,
        ClientConnected => \&client_connect,
        ClientDisconnected => \&client_disconnect,
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
                'client_input'
            ]
        ]
    );

    $self->{workers} = [];
    $self->{worker_status} = {};
    $self->{workflows} = [];
    $self->{wait_for} = {};
    $self->{session} = $session;
    
    return $self;
}

sub _client_input_stub {    
    $poe_kernel->yield('client_input', @_[ARG0..$#_]);
}

sub client_input {
    my ($input,$k,$s,$h,$self) = @_[ARG0, KERNEL, SESSION, HEAP, OBJECT];

    print Data::Dumper->new([$input])->Dump;
    if ($input->type eq 'response') {
        if ($input->heap->{original_message_id} &&
            $self->{wait_for}->{ $input->heap->{original_message_id} }) {

            my $sub = $self->{wait_for}->{ $input->heap->{original_message_id} };
            delete $self->{wait_for}->{ $input->heap->{original_message_id} };
            if (ref($sub) && ref($sub) eq 'POE::Session::AnonEvent') {
                $sub->($input);
            }
        } else {
            warn 'unusual response';
            print STDERR Data::Dumper->new([$self->{wait_for}])->Dump;
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
    my ($self, $postback, $s) = @_[OBJECT, ARG0, SESSION];
    
    push @{ $self->{workers} }, $s;
    
    $postback->(1);
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
    
    $workflow->executor(Workflow::Executor::Server->create);
    $workflow->executor->server($self);
    
    
    my $cb = sub {
        my ($data) = @_;
        warn "callback fired.";
        warn Data::Dumper->new([$data])->Dump;
    };

    $workflow->execute(
        input => $inputs,
        output_cb => $cb
    );

    $workflow->wait;
    
    $postback->(1);
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

    $self->{wait_for}->{$message->id} = $s->postback('finish_operation',$callback,$opdata);
    $h->{client}->put($message);

}

sub finish_operation {
    my ($self, $creation_args, $called_args) = @_[OBJECT, ARG0, ARG1];
    my $callback = $creation_args->[0];
    my $opdata = $creation_args->[1];
    my $message = $called_args->[0];

    $opdata->output({ %{ $opdata->output }, @{ $message->heap->{result} } });
    $opdata->is_done(1);
    
    $callback->($opdata);
}

sub test_response {
    my ($postback) = @_[ARG0];
    
    $postback->('hello world!');
}

sub client_connect {
    my ($s) = @_[SESSION];
    print $s->ID . " connect\n";
}

sub client_disconnect {
    my ($s) = @_[SESSION];
    print $s->ID . " disconnect\n";
    
    my @workers = grep { $_ != $s } 
        @{ $server_singleton->{workers} };
        
    $server_singleton->{workers} = \@workers;
}


1;
