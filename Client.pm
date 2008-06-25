
package Workflow::Client;

use strict;

use POE qw(Component::Client::TCP Filter::Reference);

sub new {
    my $class = shift;
    
    return bless({},$class);
}

sub run_worker {
    my ($class, $host, $port) = (shift, shift, shift);
    my $self = $class->create(
        $host, $port,
        [['announce_worker']]
    );

    POE::Kernel->run();
}

sub run_commands {
    my ($class, $host, $port) = (shift, shift, shift);
    my $self = $class->create(
        $host, $port,
        [@_]
    );
    
    $self->{quit_after_results} = 1;
    
    POE::Kernel->run();
}

#
#   Workflow::Client->execute_workflow(
#       xml_file => 'xml.d/sample.xml',
#       input => {
#
#       },
#       output_cb => sub { }
#   );
#

sub execute_workflow {
    my $class = shift;
    my %args = @_;
    
    my $self = $class->create(
        'localhost', 15243,
        [
            ['load_workflow', $args{xml_file}],
            ['execute_workflow', $args{input}]
        ]
    );
    
    if ($args{output_cb}) {
        $self->{output_cb} = $args{output_cb};
        $self->{quit_after_workflow_finished} = 1;
    } else {
        $self->{quit_after_results} = 1;
    }

    POE::Kernel->run() unless (exists $args{no_run});
}

sub create {
    my $class = shift;
    my $host = shift;
    my $port = shift;
    my $yc = shift;
    my $self = $class->new();

    my $session = POE::Component::Client::TCP->new(
        Alias => 'workflow client',
        RemoteAddress => $host,
        RemotePort => $port,
        Filter => 'POE::Filter::Reference',
        ServerInput => \&_server_input,
        Connected => \&_connect,
        Disconnected => \&_disconnect,
        Started => \&_start,
        Args => [$yc],
        ObjectStates => [
            $self => [ 
                '_next_command', 
                'execute', 
                'send_command_result', 
                'hangup', 
                'server_input',
                'workflow_finished',
            ]
        ]
    );

    $self->{session} = $session;

    return $self;
}

sub _server_input {    
    $poe_kernel->call($_[SESSION], 'server_input', @_[ARG0..$#_]);
}

sub server_input {
    my ($self, $input, $s, $h, $k) = @_[OBJECT, ARG0, SESSION, HEAP, KERNEL];
    
    print Data::Dumper->new([$input])->Dump;

    if ($input->type eq 'response') {
        if ($input->heap->{original_message_id} &&
            $h->{wait_for}->{ $input->heap->{original_message_id} }) {
            
            print "Server replied: " . join(',', @{ $input->heap->{result} }) . "\n";
            
            delete $h->{wait_for}->{ $input->heap->{original_message_id} };
            
            if (scalar @{ $h->{command_on_connect} }) {
                $k->yield('_next_command', @{ $input->heap->{result} });
            }
            
            if (scalar @{ $h->{command_on_connect} } == 0 &&
                scalar keys %{ $h->{wait_for} } == 0 &&
                $self->{quit_after_results}) {
                
                $k->yield('hangup');
            }
        } else {
            warn 'unusual response';
            print STDERR Data::Dumper->new([$h->{wait_for}])->Dump;
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
    
    $h->{server}->put($message);
}

sub test_response {
    my ($postback) = @_[ARG0];
    
    $postback->('hello world!');
}

sub execute {
    my ($postback, $optype) = @_[ARG0, ARG1];
    my %inputs = (@_[ARG2..$#_]);

    my $outputs = $optype->execute(%inputs);
    
    $postback->(%$outputs);
}

sub workflow_finished {
    my ($self, $k, $postback, $workflow_id, $data) = @_[OBJECT, KERNEL, ARG0, ARG1, ARG2];

    if ($self->{output_cb} && ref($self->{output_cb}) eq 'CODE') {
        $self->{output_cb}->($data);
    }

    $postback->(1);
    
    $k->yield('shutdown');
}

sub _start {
    my ($h,$yc) = @_[HEAP, ARG0];
    
    $h->{command_on_connect} = $yc;
    $h->{wait_for} = {};
}

sub _connect {
    my ($s,$h,$k) = @_[SESSION,HEAP,KERNEL];
    print $s->ID . " connect\n";

    $k->yield('_next_command');
}

sub _next_command {
    my ($s,$h,$k) = @_[SESSION,HEAP,KERNEL];

    if (@{ $h->{command_on_connect} }) { 
        my @c = @{ shift @{ $h->{command_on_connect} } };
        push @c, @_[ARG0..$#_];

        my $message = Workflow::Server::Message->create(
            type => 'command',
            heap => {
                command => shift @c,
                args => \@c
            }
        );

        $h->{server}->put($message);
        $h->{wait_for}->{$message->id} = 1;
    }
}

sub _disconnect {
    my ($s) = @_[SESSION];
    print $s->ID . " disconnect\n";
}

sub hangup {
    my ($k) = @_[KERNEL];
    
    print "hanging up now\n";
    $k->yield('shutdown');
}


1;
