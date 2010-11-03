package Cord::Server::Watchdog;

use strict;
use warnings;
use POE::Component::IKC::ClientLite;

use Cord;
class Cord::Server::Watchdog {
    has => [
        start_time => { is => 'TIMESTAMP' },
        duration => { is => 'NUMBER' },
        dispatch_identifier => { is => 'String' },
        client => { }
    ]
};

sub create {
    my $class = shift;
    my %args = (@_);
    
    $DB::single=1;
    
    my $self = $class->SUPER::create(%args);

    $self->dispatch_identifier($ENV{LSB_JOBID});

    if ($Cord::Server::Worker::client) {
        my $poe = create_ikc_client(
            ip => $Cord::Server::Worker::host,
            port => $Cord::Server::Worker::port
        );
        die "can't connect to create watchdog\n" unless $poe;
    
        my $result = $poe->call("watchdog/create",[$self->dispatch_identifier,$self->duration]) or die $poe->error;
        
        $self->client($poe);
    } ## else we're not running in the workflow environment

    return $self;
}

sub delete {
    my $self = shift;
    
    if (my $poe = $self->client) {
        my $result = $poe->call("watchdog/delete",[$self->dispatch_identifier]) or die $poe->error;
    }
    
    $self->SUPER::delete;
}

1;
