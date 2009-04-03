
use strict;
use warnings;

use Workflow;
use Workflow::Server::UR;
use Workflow::Server::Hub;

package Workflow::Command::Server;

class Workflow::Command::Server {
    is => ['Workflow::Command'],
    has_optional => [
        type => {
            is => 'String',
            default_value => 'both',
            doc => 'Type of server to run: UR,Hub or Both',
        },
# hub host is commented out because Workflow::Server::UR is hardcoded to localhost, oops
#        hub_host => {
#            is => 'String',
#            doc => 'Host running the Hub server',
#        },
        ur_port => {
            is => 'Integer',
#            default_value => $Workflow::Server::UR::port_number,
            doc => 'UR server port number',
        },
        hub_port => {
            is => 'Integer',
#            default_value => $Workflow::Server::Hub::port_number,
            doc => 'Hub server port number'
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Runs a Workflow::Server::UR or Workflow::Server::Hub process";
}

sub help_synopsis {
    return <<"EOS"
    workflow server 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

sub execute {
    my $self = shift;

    $Workflow::Server::UR::port_number = $self->ur_port
        if $self->ur_port;
    $Workflow::Server::Hub::port_number = $self->hub_port
        if $self->hub_port;

    my $type = lc($self->type);

    if ($type eq 'both') {
        # start_both

        POE::Kernel->stop();

        my $pid = fork;
        if ($pid) {
            print "Hub pid: $$\n";
            Workflow::Server::Hub->start;
        } elsif (defined $pid) {
            sleep 3;
            print "UR pid: $$\n";
            Workflow::Server::UR->start;
        } else {
            die "no child?";
        }
    } elsif ($type eq 'ur') {
#        if (defined $self->hub_host) {
            # start a UR server and connect to hub_host for dispatch 

            Workflow::Server::UR->start;

#        } else {
#            die 'must define a hub_host to start this server';
#        }
    } elsif ($type eq 'hub') {
        # start a hub server and connect 

        Workflow::Server::Hub->start;
    }

}

1;
