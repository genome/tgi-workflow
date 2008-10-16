
package Workflow::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/run_workflow run_workflow_lsf/;
our @EXPORT_OK = qw//;

our @ERROR = ();

use Workflow ();
use POE;


sub run_workflow {
    my $xml = shift;
    my %inputs = @_;

    @ERROR = ();

    my $instance;
    my $error;

    my $w = Workflow::Model->create_from_xml($xml);
    $w->execute(
        input => \%inputs,
        output_cb => sub {
            $instance = shift;
        },
        error_cb => sub {
            $error = 1;
        }
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

use Workflow::Server::UR;
use Workflow::Server::Hub;

sub run_workflow_lsf {
    my $xml = shift;
    my %inputs = @_;

    @ERROR = ();

    my $done_instance;
    my $error;

    POE::Kernel->stop();
    my $pid = fork;
    if ($pid) {
        ## parent process

        my $after_connect = sub {
        POE::Session->create(
            inline_states => {
                _start => sub {
                    my ($kernel,$session) = @_[KERNEL,SESSION];

                    $kernel->alias_set("controller");
                    $kernel->post('IKC','publish','controller',
                        [qw(got_plan_id got_instance_id complete error)]
                    );

                    $kernel->delay('startup',0);
                },
                _stop => sub {
                },
                startup => sub {
                    my ($kernel) = @_[KERNEL];

                    $kernel->post(
                        'IKC','call','poe://UR/workflow/load',
                        [$xml], 'poe:got_plan_id'
                    );
                },
                got_plan_id => sub {
                    my ($kernel, $id) = @_[KERNEL,ARG0];
#                    print "Plan: $id\n";
                    
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
#                    print "Instance: $id\n";
                },
                complete => sub {
                    my ($kernel, $arg) = @_[KERNEL, ARG0];
                    my ($id, $instance, $execution) = @$arg;

                    $done_instance = $instance;

#                    print "Complete: $id\n";
                    $kernel->post('IKC','post','poe://UR/workflow/quit');
                    $kernel->alias_remove('controller');
                },
                error => sub {
                    my ($kernel, $arg) = @_[KERNEL, ARG0];
                    my ($id, $instance, $execution) = @$arg;

#                    print "Error: $id\n";
                    $error = 1;
                    
                    $kernel->post('IKC','post','poe://UR/workflow/quit');
                    $kernel->alias_remove('controller');
                }
            }
        );
        };

        sleep 5;  ## temporary fix until i can think of how to detect if server is ready
        Workflow::Server::UR->start($after_connect);
    } elsif (defined $pid) {
        ## child process
        Workflow::Server::Hub->start;
        exit;
    } else {
        die "couldnt fork";
    }

    if (defined $error) {
        @ERROR = Workflow::Operation::InstanceExecution::Error->is_loaded;
        return undef;
    }

    unless (defined $done_instance) {
        die 'workflow did not run to completion';
    }

    return $done_instance->output;
}

1;
