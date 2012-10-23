
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
        ur_port => {
            is => 'Integer',
            default_value => 14401,
            doc => 'UR server port number',
        },
        hub_port => {
            is => 'Integer',
            default_value => 14400,
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
} # yet we use it in production code... :( see Workflow::Server::Remote

sub execute {
    my $self = shift;

    my $type = lc($self->type);

    if ($type eq 'both') {
        # start_both
        POE::Kernel->stop(); # ??

        my $pid = fork;
        if ($pid) {
            # parent
            print "Hub pid: $$\n";
            Workflow::Server::Hub->start(ur_port  => $self->ur_port,
                                         hub_port => $self->hub_port);
        } elsif (defined $pid) {
            # child
            sleep 3; # ??
            print "UR pid: $$\n";
            Workflow::Server::UR->start(ur_port  => $self->ur_port,
                                        hub_port => $self->hub_port);
        } else {
            # bad
            die "no child?";
        }
    } elsif ($type eq 'ur') {
        # changes name in ps command.
        $0 = 'workflow urd ' . $self->ur_port;
        Workflow::Server::UR->start(ur_port  => $self->ur_port,
                                        hub_port => $self->hub_port);
    } elsif ($type eq 'hub') {
        # start a hub server and connect 
        $0 = 'workflow hubd ' . $self->hub_port; 
        Workflow::Server::Hub->start(ur_port  => $self->ur_port,
                                     hub_port => $self->hub_port);
    }
}

1;
