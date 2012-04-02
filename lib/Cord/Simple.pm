
package Cord::Simple;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/run_workflow run_workflow_lsf resume_lsf/;
our @EXPORT_OK = qw//;

our @ERROR = ();
our $override_lsf_use = 0;
our $server_location_file;

if (defined $ENV{NO_LSF} && $ENV{NO_LSF}) {
    $override_lsf_use = 1;
}

use strict;

use Cord ();
use Guard;
use Cord::Server;
use Cord::Server::Remote;
use POSIX ":sys_wait_h";

sub run_workflow {
    my $xml = shift;
    my %inputs = @_;

    @ERROR = ();

    my $instance;
    my $error;

    my $w;
    if (ref($xml) && UNIVERSAL::isa($xml,'Cord::Operation')) {
        $w = $xml;
    } else {
        $w = Cord::Operation->create_from_xml($xml);
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
        @ERROR = Cord::Operation::InstanceExecution::Error->is_loaded;    
        return undef;
    }

    unless ($instance) {
        die 'workflow did not run to completion';
    }

    return $instance->output;
}

use Cord::Operation::Instance;
use Cord::Model::Instance;

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

    my ($r, $guards) = Cord::Server::Remote->launch;
    die "Failed to get a Cord::Server::Remote from launch.\n" unless ($r);
    my $g = _advertise($r);

    my $response;
    handle_child_exit {
        $response = $r->simple_resume($id);
    } sub { undef $g; undef $guards; };

    $r->end_child_servers($guards);

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

    my $xml = shift;
    my %inputs = @_;

    if (ref($xml)) {
        if (ref($xml) eq 'GLOB') {
            my $newxml = '';        
            while (my $line = <$xml>) {
                $newxml .= $line;
            }
            $xml = $newxml;
        } elsif (UNIVERSAL::isa($xml,'Cord::Operation')) {
            $xml = $xml->save_to_xml;
        }
    }
    @ERROR = ();

    my ($r, $guards) = Cord::Server::Remote->launch;
    die "Failed to get a Cord::Server::Remote from launch.\n" unless ($r);
    my $g = _advertise($r);    

    my $response;
    handle_child_exit {
        $response = $r->simple_start($xml,\%inputs);
    } sub { undef $g; undef $guards };
    $r->end_child_servers($guards);

    if (scalar @$response == 3) {
        return $response->[1];

    } elsif (scalar @$response == 4) {
        @ERROR = @{ $response->[3] };
        return undef;
    }

    die 'confused';
}

sub _advertise {
    my ($r) = @_;
    my $g;
    if (defined $server_location_file) {
        open FH, ('>' . $server_location_file);
        print FH $r->host . ':' . $r->port . "\n";
        close FH;
        $g = guard { unlink $server_location_file };
    }
    return $g;
}

1;
