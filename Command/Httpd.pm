
use strict;
use warnings;

use Workflow;
use Workflow::Server::HTTPD;
use POE qw(Component::IKC::Client);
use Sys::Hostname ();

package Workflow::Command::Httpd;

class Workflow::Command::Httpd {
    is => ['Workflow::Command'],
    has => [
        host => {
            is => 'String',
            doc => 'Host running the UR server',
            is_optional => 1
        },
        port => {
            is => 'Integer',
            is_optional => 1,
            default_value => 13425,
            doc => 'TCP port number of the UR server.  Default is 13425',
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Web based object browser for workflow servers";
}

sub help_synopsis {
    return <<"EOS"
    workflow show 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

sub execute {
    my $self = shift;

    my $hostname = Sys::Hostname::hostname;
    my $port = 8088;

    print "URL: http://$hostname:$port/\n";

    Workflow::Server::HTTPD->setup;

    POE::Kernel->run;
}

1;
