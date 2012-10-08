package Workflow::Command::StartHub;

use strict;
use warnings;

use Workflow;
use Workflow::Server::Hub;

class Workflow::Command::StartHub {
    is => ['Workflow::Command'],
    has => [
        announce_location_fifo => {
            is => 'String',
            doc => "Filename that allows the hub to communicate it's location (once it starts up).",
        },
    ]
};

sub help_brief {
    "Runs a Workflow::Server::Hub process";
}

sub execute {
    my ($self) = @_;

    Workflow::Server::Hub->setup($self->announce_location_fifo);
    Workflow::Server::Hub->start();
}
