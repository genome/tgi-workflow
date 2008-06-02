
package Workflow::Client;

use strict;
use POE qw(Component::Client::TCP Filter::Reference);

sub new {
    my $class = shift;
    
    return bless({},$class);
}

sub run_worker {
    my $self = shift->create(
        [['announce_worker']]
    );

    POE::Kernel->run();
    exit;
}

sub run_commands {
    my $class = shift;
    my $self = $class->create(
        [@_]
    );
    
    POE::Kernel->run();
    exit;
}

sub create {
    my $class = shift;
    my $yc = shift;
    my $self = $class->new();

    my $session = POE::Component::Client::TCP->new(
        Alias => 'workflow client',
        RemoteAddress => 'localhost',
        RemotePort => 15243,
        Filter => 'POE::Filter::Reference',
        ServerInput => \&server_input,
        Connected => \&_connect,
        Disconnected => \&_disconnect,
        Started => \&_start,
        Args => [$yc],
        ObjectStates => [
            $self => [ '_next_command', 'execute', 'send_command_result' ]
        ]
    );

    $self->{session} = $session;

    return $self;
}

sub server_input {
    my ($input, $s, $h, $k) = @_[ARG0, SESSION, HEAP, KERNEL];
    
    print Data::Dumper->new([$input])->Dump;

    if ($input->type eq 'response') {
        if ($input->heap->{original_message_id} &&
            $h->{wait_for}->{ $input->heap->{original_message_id} }) {
            
            print "Server replied: " . join(',', @{ $input->heap->{result} }) . "\n";
            
            delete $h->{wait_for}->{ $input->heap->{original_message_id} };
            
            if (scalar @{ $h->{command_on_connect} }) {
                $k->yield('_next_command', @{ $input->heap->{result} });
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


1;
