
use strict;
use warnings;

use Cord;
use Cord::Server::UR;
use Cord::Server::Hub;

package Cord::Command::Server;

class Cord::Command::Server {
    is => ['Cord::Command'],
    has_optional => [
        type => {
            is => 'String',
            default_value => 'both',
            doc => 'Type of server to run: UR,Hub or Both',
        },
# hub host is commented out because Cord::Server::UR is hardcoded to localhost, oops
#        hub_host => {
#            is => 'String',
#            doc => 'Host running the Hub server',
#        },
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
    "Runs a Cord::Server::UR or Cord::Server::Hub process";
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

    my $type = lc($self->type);

    if ($type eq 'both') {
        # start_both

        POE::Kernel->stop();

        my $pid = fork;
        if ($pid) {
            print "Hub pid: $$\n";
            Cord::Server::Hub->start(ur_port => $self->ur_port, hub_port => $self->hub_port);
        } elsif (defined $pid) {
            sleep 3;
            print "UR pid: $$\n";
            Cord::Server::UR->start(ur_port => $self->ur_port, hub_port => $self->hub_port);
        } else {
            die "no child?";
        }
    } elsif ($type eq 'ur') {

            $0 = 'workflow urd ' . $self->ur_port;

            Cord::Server::UR->start(ur_port => $self->ur_port, hub_port => $self->hub_port);

    } elsif ($type eq 'hub') {
        # start a hub server and connect 

        $0 = 'workflow hubd ' . $self->hub_port; 

        Cord::Server::Hub->start(ur_port => $self->ur_port, hub_port => $self->hub_port);
    }

}

1;
