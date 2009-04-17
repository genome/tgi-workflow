
package Workflow::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/run_workflow run_workflow_lsf resume_lsf/;
our @EXPORT_OK = qw//;

our @ERROR = ();
our $start_servers = 1;
our $connect_port = 13425;
our $store_db = 1;
our $override_lsf_use = 0;

if (defined $ENV{NO_LSF} && $ENV{NO_LSF}) {
    $override_lsf_use = 1;
}

use Workflow ();
use IPC::Run;
use UR::Util;

use Workflow::Server;
use POE::Component::IKC::ClientLite;
use Socket;

sub run_workflow {
    my $xml = shift;
    my %inputs = @_;

    @ERROR = ();

    my $instance;
    my $error;

    my $w;
    if (ref($xml) && UNIVERSAL::isa($xml,'Workflow::Operation')) {
        $w = $xml;
    } else {
        $w = Workflow::Model->create_from_xml($xml);
    }
    $w->execute(
        input => \%inputs,
        output_cb => sub {
            $instance = shift;
        },
        error_cb => sub {
            $error = 1;
        },
        store => $store_db ? Workflow::Store::Db->get : Workflow::Store::None->get
    );
 
    $w->wait;

    if (defined $error) {
        @ERROR = Workflow::Operation::InstanceExecution::Error->is_loaded;    
        return undef;
    }

    unless ($instance) {
        die 'workflow did not run to completion';
    }

    return $instance->output;
}

use Workflow::Store::Db::Operation::Instance;
use Workflow::Store::Db::Model::Instance;

sub resume_lsf {
    return resume(@_) if ($override_lsf_use);
    
    my $id = shift;
    
    @ERROR = ();

    my @libs = UR::Util::used_libs();
    my $libstring = '';
    foreach my $lib (@libs) {
        $libstring .= 'use lib "' . $lib . '"; ';
    }

    Workflow::Server->lock('Simple');

    my $ur_port = 13425;
    while (!is_port_available($ur_port)) {
        $ur_port+=2;
    }

    my $hub_port = 13424;
    while (!is_port_available($hub_port)) {
        $hub_port+=2;
    }

    my @hubcmd = ('perl','-e',$libstring . 'use Workflow::Server::Hub; $Workflow::Server::Hub::port_number=' . $hub_port . '; Workflow::Server::Hub->start;');
    my @urcmd = ('perl','-e',$libstring . 'use Workflow::Server::UR; $Workflow::Server::Hub::port_number=' . $hub_port . '; $Workflow::Server::UR::port_number=' . $ur_port . '; $Workflow::Server::UR::store_db=' . $store_db . ';Workflow::Server::UR->start;');

    Workflow::Server->lock('Hub');
    Workflow::Server->lock('UR');

    my $h;
    if ($start_hub_server) {
        $h = IPC::Run::start(\@hubcmd);
        Workflow::Server->wait_for_lock('Hub');
    }
        
    $start_ur_server = 1 if $start_hub_server == 1;
    
    my $u;
    if ($start_ur_server) {
        $u = IPC::Run::start(\@urcmd);
        Workflow::Server->wait_for_lock('UR');
    }

    Workflow::Server->unlock('Simple');

    my $poe = create_ikc_client(
        port    => $ur_port,
        timeout => 1209600 
    );

    my $response = $poe->post_respond('workflow/simple_resume',[$id]);

    $poe->post('workflow/quit',1);

    $u->finish if $start_ur_server && $fork_ur_server;
    $h->finish if $start_hub_server;

    $poe->disconnect;

    unless (defined $response) {
        die 'unexpected response';
    }

    if (scalar @$response == 3) {
        return $response->[1]->output;

    } elsif (scalar @$response == 4) {
        @ERROR = @{ $response->[3] };
        return undef;
    }

    die 'confused';
}

sub run_workflow_lsf {
    return run_workflow(@_) if ($override_lsf_use);

    my $xml = shift;
    my %inputs = @_;

    if (ref($xml)) {
        if (ref($xml) eq 'GLOB') {
            my $newxml = '';        
            while (my $line = <$xml>) {
                $newxml .= $line;
            }
            $xml = $newxml;
        } elsif (UNIVERSAL::isa($xml,'Workflow::Operation')) {
            $xml = $xml->save_to_xml;
        }
    }

    @ERROR = ();

    my $u;
    my $h;
    
    my $ur_port_used;
    if ($start_servers) {
        my @libs = UR::Util::used_libs();
        my $libstring = '';
        foreach my $lib (@libs) {
            $libstring .= 'use lib "' . $lib . '"; ';
        }

        Workflow::Server->lock('Simple');

        my $ur_port = 13425;
        while (!is_port_available($ur_port)) {
            $ur_port+=2;
        }

        my $hub_port = 13424;
        while (!is_port_available($hub_port)) {
            $hub_port+=2;
        }

        my @hubcmd = ('perl','-e',$libstring . 'use Workflow::Server::Hub; $Workflow::Server::Hub::port_number=' . $hub_port . '; Workflow::Server::Hub->start;');
        my @urcmd = ('perl','-e',$libstring . 'use Workflow::Server::UR; $Workflow::Server::Hub::port_number=' . $hub_port . '; $Workflow::Server::UR::port_number=' . $ur_port . '; $Workflow::Server::UR::store_db=' . $store_db . ';Workflow::Server::UR->start;');

        Workflow::Server->lock('Hub');
        Workflow::Server->lock('UR');

        $h = IPC::Run::start(\@hubcmd);
        Workflow::Server->wait_for_lock('Hub');

        $u = IPC::Run::start(\@urcmd);
        Workflow::Server->wait_for_lock('UR');

        $ur_port_used = $ur_port;

        Workflow::Server->unlock('Simple');
    } else {
        $ur_port_used = $connect_port;
    }

    my $poe = create_ikc_client(
        port    => $ur_port_used,
        timeout => 1209600 
    );

    my $response = $poe->post_respond('workflow/simple_start',[$xml,\%inputs]);

    if ($start_servers) {
        $poe->post('workflow/quit',1);

        $u->finish if $start_ur_server && $fork_ur_server;
        $h->finish if $start_hub_server;
    }

    $poe->disconnect;

    unless (defined $response) {
        die 'unexpected response';
    }

    if (scalar @$response == 3) {
        return $response->[1]->output;

    } elsif (scalar @$response == 4) {
        @ERROR = @{ $response->[3] };
        return undef;
    }

    die 'confused';
}

sub is_port_available {
    my $port = shift;
    
    socket(TESTSOCK,PF_INET,SOCK_STREAM,6);
    setsockopt(TESTSOCK,SOL_SOCKET,SO_REUSEADDR,1);
    
    my $val = bind(TESTSOCK, sockaddr_in($port, INADDR_ANY));
    
    shutdown(TESTSOCK,2);
    close(TESTSOCK);
    
    return 1 if $val;
    return 0;
}

1;
