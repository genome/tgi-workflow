
package Workflow::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/run_workflow run_workflow_lsf/;
our @EXPORT_OK = qw//;

our @ERROR = ();
our $start_ur_server = 1;
our $start_hub_server = 1;
our $fork_ur_server = 1;
our $store_db = 1;

use Workflow ();
use IPC::Run;

sub POE::Kernel::ASSERT_EVENTS () { 1 };
use POE qw(Component::IKC::Client);

sub evTRACE () { 0 };

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

sub run_workflow_lsf {
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

    my $done_instance;
    my $error;
    my $error_list;

    my @hubcmd = ('perl','-e','use above; use Workflow::Server::Hub; Workflow::Server::Hub->start;');
    my @urcmd = ('perl','-e','use lib "/gscuser/eclark/lib"; use above; use Workflow::Server::UR; $Workflow::Server::UR::store_db=' . $store_db . ';Workflow::Server::UR->start;');

    my $h;
    if ($start_hub_server) {    
        $h = IPC::Run::start(\@hubcmd);
        sleep 3;
    }
    
    $start_ur_server = 1 if $start_hub_server == 1;
    
    my $u;
    if ($start_ur_server && $fork_ur_server) {
        $u = IPC::Run::start(\@urcmd);
        sleep 3;
    }

    my $after_connect = sub {
        my $channel_id = shift;
        
        POE::Session->create(
            heap => {
                channel => $channel_id
            },
            inline_states => {
                _start => sub {
                    my ($kernel,$session) = @_[KERNEL,SESSION];
evTRACE and print "controller _start\n";

                    $kernel->alias_set("controller");
                    $kernel->post('IKC','publish','controller',
                        [qw(got_plan_id got_instance_id complete error)]
                    );

                    $kernel->yield('startup');
                },
                _stop => sub {
evTRACE and print "controller _stop\n";
                },
                startup => sub {
                    my ($kernel) = @_[KERNEL];
evTRACE and print "controller startup\n";                    
                    
                    $kernel->call(
                        'IKC','call','poe://UR/workflow/load',
                        [$xml], 'poe:got_plan_id'
                    );
                },
                got_plan_id => sub {
                    my ($kernel, $id) = @_[KERNEL,ARG0];
evTRACE and print "controller got_plan_id $id\n";
                    
                    my $kernel_name = $kernel->ID;

                    $_[KERNEL]->post(
                        'IKC','call',
                        'poe://UR/workflow/execute',
                        [
                            $id,
                            \%inputs,
                            "poe://$kernel_name/controller/complete",
                            "poe://$kernel_name/controller/error"
                        ],
                        'poe:got_instance_id'
                    );
                },
                got_instance_id => sub {
                    my ($kernel, $id) = @_[KERNEL, ARG0];
evTRACE and print "controller got_instance_id $id\n";
                },
                complete => sub {
                    my ($kernel, $arg) = @_[KERNEL, ARG0];
                    my ($id, $instance, $execution) = @$arg;
evTRACE and print "controller complete $id\n";

                    $done_instance = $instance;
                    
                    $kernel->yield('quit');
                },
                error => sub {
                    my ($kernel, $arg) = @_[KERNEL, ARG0];
                    my ($id, $instance, $execution, $errors) = @$arg;
evTRACE and print "controller error $id\n";

                    $error = 1;
                    $error_list = $errors;

                    $kernel->yield('quit');
                },
                quit => sub {
                    my ($kernel, $heap) = @_[KERNEL, HEAP];
evTRACE and print "controller quit\n";
                    
                    $kernel->post('IKC','post','poe://UR/workflow/quit', $start_hub_server)
                        if $start_ur_server;

                    # channel is not set if the UR server and client are in the same process
                    $kernel->post($heap->{channel},'shutdown') 
                        if ($heap->{channel});
                }
            }
        );
    };

    my $client_session;
    if ($start_ur_server && !$fork_ur_server) {
        # keep it in this process, hope you want your current context committed
        
        require Workflow::Server::UR;

        $Workflow::Server::UR::store_db=$store_db;
        Workflow::Server::UR->start($after_connect);
    } else {
        # otherwise just try to connect to anything that i can find
        
        $client_session = POE::Component::IKC::Client->spawn( 
        #    ip=>'linusop15.gsc.wustl.edu', 
            port=>13425,
            name=>'Controller',
            on_connect=>sub { $after_connect->($poe_kernel->get_active_session()->ID) }
        );
    }

    POE::Kernel->run();

    # Should probably consider this a bug in cpan.  They shouldn't keep 
    # this in a global and not reset it on shutdown
    $POE::Component::IKC::Responder::ikc = undef;

    $u->finish if $start_ur_server && $fork_ur_server;
    $h->finish if $start_hub_server;

    if (defined $error) {
        @ERROR = @$error_list;
        return undef;
    }

    unless (defined $done_instance) {
        die 'workflow did not run to completion';
    }

    return $done_instance->output;
}

1;
