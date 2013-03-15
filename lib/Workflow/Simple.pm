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
use Data::Dumper;
use Guard;
use File::Slurp qw/read_file/;
use Workflow::Server;
use Workflow::Server::Remote;
use XML::Simple;
use File::Temp;
use File::Basename;
use File::Spec;
use POSIX ":sys_wait_h"; # for non-blocking read

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
    if ($ENV{WF_USE_FLOW}) {
        return run_workflow_flow(@_)
    }

    return run_workflow(@_) if ($override_lsf_use);

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


sub _op_resource_requests {
    my $op = shift;
    if (!exists $op->{operationtype}) {
        die "Operation $op->{name} with no operation type!";
    }

    my %rv;

    my $optype = $op->{operationtype};
    my %lsf;
    if (exists $optype->{lsfQueue}) {
        $lsf{queue} = $optype->{lsfQueue};
    }

    if (exists $optype->{lsfResource}) {
        my $res = Workflow::LsfParser::get_resource_from_lsf_resource(
                $optype->{lsfResource})->as_xml_simple_structure;
        my $queue_override = delete $res->{queue};
        $lsf{queue} = $queue_override if $queue_override;
        $lsf{resource} = Flow::translate_workflow_resource(%$res);
    }

    if (%lsf) {
        %rv = ($op->{name} => \%lsf);
    }

    if (exists $op->{operation}) {
        %rv = (%lsf, map {_op_resource_requests($_)} @{$op->{operation}});
    }

    return %rv
}

sub run_workflow_flow {
    require Flow;

    my ($wf_repr, %inputs) = @_;

    my $xml_text;
    my @force_array = qw/operation property inputproperty outputproperty link/;

    my $r = ref($wf_repr);
    if ($r) {
        if ($r eq 'GLOB') {
            $xml_text = $wf_repr;
        } elsif (UNIVERSAL::isa($wf_repr, 'Workflow::Operation')) {
            $xml_text = $wf_repr->save_to_xml;
        } else {
            die 'unrecognized reference';
        }
    } elsif (-s $wf_repr) {
        $xml_text = read_file($wf_repr);
    } else {
        $xml_text = $wf_repr;
    }

    my $xml = XMLin($xml_text, KeyAttr => [], ForceArray => \@force_array);

    my %resources;
    if (exists $xml->{operation} and ref $xml->{operation} eq 'ARRAY') {
        my @ops = @{$xml->{operation}};
        %resources = (map { _op_resource_requests($_) } @ops);
    } else {
        %resources = _op_resource_requests($xml);
    }

    #save xml as file
    my $fh = File::Temp->new();
    $fh->print($xml_text);
    $fh->close();
    my $filename = $fh->filename;

    my $executable = File::Spec->join(File::Basename::dirname(__FILE__), 'Cache', 'save.pl');
    my $plan_id = `$^X $executable $filename`;
    if ($? or not $plan_id) {
        die "'$^X $executable $filename' did not return successfully";
    }
    chomp($plan_id);

    return Flow::run_workflow($xml_text, \%inputs, \%resources, $plan_id);
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
