
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
        hostname => {
            is => 'String',
            doc => 'Hostname running the UR server',
        },
        port => {
            is => 'Integer',
            doc => 'TCP port number of the UR server',
        }
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Show";
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

    print "Connected to UR server: " . $self->hostname . ':' . $self->port . "\n\nhttp://$hostname:$port/\n\n";

    my $client = POE::Component::IKC::Client->spawn(
        ip => $self->hostname,
        port => $self->port,
        name => 'HTTPD',
        on_connect => sub {
            Workflow::Server::HTTPD->setup;
        }
    );

    POE::Kernel->run;
}

1;
