
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

    my $connected = 0;
    print "Connecting to UR server: " . $self->host . ':' . $self->port . "\n\nhttp://$hostname:$port/\n\n";

    my $client = POE::Component::IKC::Client->spawn(
        ip => $self->host,
        port => $self->port,
        name => 'HTTPD',
        on_connect => sub {
            $connected =1;
            Workflow::Server::HTTPD->setup;
        }
    );

    POE::Kernel->run;

    unless ($connected) {
        print "Can't connect!\n";
        return 0;
    };
}

1;
