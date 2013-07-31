package Workflow::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/run_workflow run_workflow_lsf resume_lsf/;
our @EXPORT_OK = qw//;

our @ERROR = ();
our $server_location_file; # see _advertise

our $override_lsf_use = 0;
if (defined $ENV{NO_LSF} && $ENV{NO_LSF}) {
    $override_lsf_use = 1;
}

use strict;

use Workflow ();
use Guard;
use Workflow::Server;
use Workflow::Server::Remote;
use XML::Simple;
use POSIX ":sys_wait_h"; # for non-blocking read
use Workflow::FlowAdapter;

sub run_workflow {
    if ($ENV{WF_USE_FLOW}) {
        return run_workflow_flow(0, @_);
    }

    my $xml = shift;
    my %inputs = @_;

    @ERROR = ();

    my $instance;
    my $error;

    my $w;
    if (ref($xml) && UNIVERSAL::isa($xml,'Workflow::Operation')) {
        $w = $xml;
    } else {
        $w = Workflow::Operation->create_from_xml($xml);
    }
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

use Workflow::Operation::Instance;
use Workflow::Model::Instance;

## nukes the guards if a child exits (killing others)
sub handle_child_exit (&&) {
    my $coderef = shift;
    my $nukeref = shift;

    my $old_chld = $SIG{CHLD};
    my $reaper;
    $reaper = sub {
        my $child;
        while (($child = waitpid(-1, WNOHANG)) > 0) {
            $nukeref->();
            die 'child exited early';
        }
        $SIG{CHLD} = $reaper;
    };
    $SIG{CHLD} = $reaper;

    $coderef->();
    $SIG{CHLD} = $old_chld;
}

sub resume_lsf {
    return resume(@_) if ($override_lsf_use);

    my $id = shift;
    @ERROR = ();

    my ($remote, $processes, $guards) = Workflow::Server::Remote->launch();
    die "Failed to get a Workflow::Server::Remote from launch.\n" unless ($remote);
    my $g = _advertise($remote);

    my $response;
    handle_child_exit {
        $response = $remote->resume($id);
    } sub { undef $g; undef $processes; undef $guards; };

    $remote->end_child_servers($processes, $guards);

    if (scalar @$response == 3) {
        return $response->[1];

    } elsif (scalar @$response == 4) {
        @ERROR = @{ $response->[3] };
        return undef;
    }

    die 'confused';
}

sub run_workflow_lsf {
    return run_workflow(@_) if ($override_lsf_use);

    if ($ENV{WF_USE_FLOW}) {
        return run_workflow_flow(1, @_);
    }

    # $xml can be either an xml formatted string, a GLOB ref or a Workflow::Operation.
    my $xml = shift;
    my %inputs = @_;

    # in case $xml is a GLOB ref or a Workflow::Operation
    my $xml_ref = ref($xml);
    if($xml_ref) {
        if($xml_ref eq 'GLOB') {
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

    my ($remote, $processes, $guards) = Workflow::Server::Remote->launch();
    unless($remote) {
        die "Failed to get a Workflow::Server::Remote from launch.\n";
    }

    my $g = _advertise($remote);

    my $response;
    handle_child_exit {
        $response = $remote->start($xml,\%inputs);
    } sub { undef $g; undef $processes; undef $guards };
    $remote->end_child_servers($processes, $guards);

    # see Workflow::Server::UR::_workflow_output_relay
    if (scalar @$response == 3) {
        return $response->[1];

    # see Workflow::Server::UR::_workflow_error_relay
    } elsif (scalar @$response == 4) {
        @ERROR = @{ $response->[3] };
        return undef;
    }

    die 'confused';
}

sub _advertise {
    my ($remote) = @_;
    my $g;
    # NOTE this is only used by 'genome model build restart' to ensure that
    # only one workflow server is spawned per build.
    if(defined $server_location_file) {
        open FH, ('>' . $server_location_file);
        print FH $remote->host . ':' . $remote->port . "\n";
        close FH;
        $g = guard { unlink $server_location_file };
    }
    return $g;
}

1;
