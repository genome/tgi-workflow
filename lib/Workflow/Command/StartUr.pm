package Workflow::Command::StartUr;

use strict;
use warnings;

use Workflow;
use Workflow::Server::UR;

class Workflow::Command::StartUr {
    is => ['Workflow::Command'],
    has => [
        hub_port => {
            is => 'Number',
            doc => 'The port on which to communicate to the Hub server.',
        },
        hub_hostname => {
            is => 'String',
            doc => 'The hostname on which the Hub server resides.',
        },
    ]
};

sub help_brief {
    "Runs a Workflow::Server::UR process";
}

sub execute {
    my ($self) = @_;

    Workflow::Server::UR->setup($self->hub_hostname, $self->hub_port);
    Workflow::Server::UR->start();
}
