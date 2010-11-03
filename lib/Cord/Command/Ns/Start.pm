package Cord::Command::Ns::Start;

use strict;
use warnings;

use Cord ();

class Cord::Command::Ns::Start {
    is  => ['Cord::Command'],
    has => [
        plan_file => {
            shell_args_position => 1,
            doc                 => 'Plan xml file to use'
        },
        input_key_value => {
            shell_args_position => 2,
            is_many             => 1,
            doc                 => 'Inputs to the workflow as key=value pairs'
        },
        debug => {
            is_optional => 1,
            doc => 'workflow path string to debug point'
        },
        done_command => {
            is_optional => 1,
            doc         => 'Command class to run on successful finish'
        },
        job_group => {
            is_optional => 1,
            doc         => 'LSF job group for all processes'
        }
    ]
};

sub execute {
    my $self = shift;

    my $xauth;
    if ($self->debug) {
        $xauth = $self->xauth_token();
    }

    unless ( -f $self->plan_file and -r _ ) {
        $self->error_message("Plan file not readable");
        return 0;
    }

    ## print args for posterity

    $self->status_message(
        sprintf( "Starting new workflow: %s\n", $self->plan_file ) );

    $self->status_message(
        sprintf( "Done command: %s\n",
            defined $self->done_command ? $self->done_command : 'undef' )
    );

    $self->status_message(
        sprintf( "Job Group: %s\n",
            defined $self->job_group ? $self->job_group : 'undef' )
    );

    $self->status_message("Input Key Value Pairs:\n");

    my %inputs = map { split( /=/, $_, 2 ); } $self->input_key_value;
    while ( my ( $k, $v ) = each %inputs ) {
        $self->status_message( sprintf( "  %-20s: %s\n", $k, $v ) );
    }

    ## load and validate plan

    my $wf_plan = Cord::Operation->create_from_xml( $self->plan_file );

    unless ( $self->validate_workflow($wf_plan) ) {
        $self->error_message("Cannot execute invalid plan");
        return 0;
    }

    ## validate inputs against plan
    
    {
        my %ikeys = map { $_ => 1 } keys %inputs;
        foreach my $k (@{ $wf_plan->operation_type->input_properties }) {
            delete $ikeys{$k} if exists $ikeys{$k};
        }

        if (scalar keys %ikeys) {
            $self->error_message('execute: Extra inputs provided: ' . join (', ', keys %ikeys));
            return 0;
        }
    }

    ## load and validate done plan

    my $done_plan;
    if ( my $done_class = $self->done_command ) {
        $done_plan = Cord::Operation->create(
            name           => $wf_plan->name . ' done',
            operation_type => Cord::OperationType::Command->get($done_class)
        );

        unless ( $self->validate_workflow($done_plan) ) {
            $self->error_message("Cannot execute invalid done plan");
            return 0;
        }
    }

    ## create operation instance for plan and done plan

    my $wf_instance =
      Cord::Operation::Instance->create( operation => $wf_plan );

    $wf_instance->input( \%inputs );
    $wf_instance->output( {} );

    ## launch

    if ($self->debug) {
        my $pathstr = $self->debug;
        ## get_by_path is designed for id's or names. id's are useless here
        #  since the objects just got created.  so we should add the * for
        #  people automatically

        if (index($pathstr,'*') != 0) {
            $pathstr = '*' . $pathstr;
        }
        $pathstr =~ s/\/(?!\*)/\/\*/g;

        my @all = $wf_instance->get_by_path($pathstr);

        for (@all) {
            $_->debug_mode(1);
        }
    }

    my $r = $self->bsub_operation($xauth, $wf_instance, $wf_instance);

    if ($wf_instance->can("child_instances")) {
        $wf_instance->current->status('running');
    }

    ## bsub ended handler

    my $job_id = $self->bsub_end_handler($wf_instance->id, $r->[2], $r->[1]);

    ## bsub done handler

    if ($done_plan) {
        my $done_instance =
          Cord::Operation::Instance->create( operation => $done_plan );

        $done_instance->input( { operation_id => $wf_instance->id } );
        $done_instance->output( {} );

        my $r =
          $self->bsub_operation( $xauth, $done_instance, $done_instance, $job_id);

    }

    # TODO bresume all jobs started.

    1;
}

sub bsub_operation {
    my ( $self, $xauth, $top, $op, @dependency ) = @_;

    if ( $op->can("child_instances") ) {
        my %deps = map { $_->id => [ $_, {} ]; } $op->child_instances;

        # organize deps and run all
        foreach my $k ( keys %deps ) {
            my $op = $deps{$k}->[0];
            my @d  = $op->depended_on_by;

            foreach my $d (@d) {
                $deps{$k}->[1]->{ $d->id } = 1;
            }

            my $r = $self->bsub_operation( $xauth, $top, $deps{$k}->[0] );
            $deps{$k}->[2] = $r;
        }

        # set deps in lsf

        my @fjobs = ();
        my @ljobs = ();
        my @jobs  = ();
        foreach my $k ( keys %deps ) {
            if ( $deps{$k}->[0]->name eq 'output connector' ) {
                push @ljobs, @{ $deps{$k}->[2]->[2] };
            }
            push @jobs,
              @{ $deps{$k}->[2]->[1]
              };    ## slurp all jobs from the inner wf into me

            my @deps = map {
                @{ $deps{$_}->[2]->[2]
                  }    ## be dependent on all the final jobs of the operation
            } keys %{ $deps{$k}->[1] };

            if ( @deps == 0 ) {
                ## i must be one of the first jobs, i have no deps
                push @fjobs, @{ $deps{$k}->[2]->[0] };

                if ( @dependency > 0 ) {    ## use deps passed in from above
                    foreach my $me ( @{ $deps{$k}->[2]->[0] } ) {   ## see below
                        $self->bmod_deps( $me, @dependency );
                    }
                } else {
                    $deps{$k}->[0]->current->status('scheduled');
                }
            } else {
                ## the first jobs of this step are each dependent on every final job of the previous steps
                foreach my $me ( @{ $deps{$k}->[2]->[0] } ) {
                    $self->bmod_deps( $me, @deps );
                }
            }
        }

        return [ \@fjobs, \@jobs, \@ljobs ];
    }

    ## bsub runner
    my $job_id = $self->bsub_runner( $xauth, $top, $op, @dependency );

    return [ [$job_id], [$job_id], [$job_id] ];
}

sub job_group_arg {
    my $self = shift;

    my $job_group = '-g /workflow/ns';    # . $self->top_id;
    if ( $self->job_group && $self->job_group ne '' ) {
        $job_group = '-g ' . $self->job_group;
    }

    return $job_group;
}

sub dep_expr_arg {
    my ( $self, @dependency ) = @_;

    my $dep_expr = '';
    if ( @dependency > 0 ) {
        my @d = map { "done($_)" } @dependency;
        $dep_expr = '-w "' . join( ' && ', @d ) . '"';
    }

    return $dep_expr;
}

sub bsub_runner {
    my ( $self, $xauth, $top, $op, @dependency ) = @_;

    my $queue = 'long';
    if ( $op->operation_type->can('lsf_queue')
        and my $rqueue = $op->operation_type->lsf_queue )
    {
        if ( $rqueue ne '' ) {
            $queue = $rqueue;
        }
    }

    my $resource = '';
    if ( $op->operation_type->can('lsf_resource')
        and my $rr = $op->operation_type->lsf_resource )
    {

        if ( $rr ne '' ) {
            $resource = index( $rr, '-' ) == 0 ? $rr : '-R "' . $rr . '"';
        }
    }

    my $job_group = $self->job_group_arg;
    my $dep_expr  = $self->dep_expr_arg(@dependency);

    my $dstr = '';
    if ($self->debug && $op->debug_mode) {
        $dstr = ' --debug';
        if ($xauth) {
            $dstr .= ' --xauth=' . $xauth;
        }
    }

    my $cmd =
      sprintf( "bsub -H -u \"eclark\@genome.wustl.edu\" -q %s %s %s %s -Q \"5 88\" workflow ns internal run%s %s %s",
        $queue, $resource, $job_group, $dep_expr, $dstr, $top->id, $op->id );

    $self->status_message("lsf\$ $cmd\n");

    my $bsub_output = `$cmd`;

    $self->status_message($bsub_output);

    # Job <8833909> is submitted to queue <long>.
    if ( $bsub_output =~ /^Job <(\d+)> is submitted to queue <(\w+)>\./ ) {

        $op->current->dispatch_identifier($1);
        return $1;
    } else {
        die 'cant launch!';
    }
}

sub bmod_deps {
    my ( $self, $id, @dependency ) = @_;

    Carp::confess('no deps') unless @dependency > 0;

    my $dep_expr = $self->dep_expr_arg(@dependency);

    my $cmd = sprintf( "bmod %s %s", $dep_expr, $id );

    $self->status_message("lsf\$ $cmd\n");

    my $bmod_output = `$cmd`;
    $self->status_message($bmod_output);

    return 1;
}

sub bsub_end_handler {
    my ($self, $id, $done, $exit) = @_;

    my $job_group = $self->job_group_arg;

    my @d = map { "done($_)" } @$done;
    my @e = map { "exit($_)" } @$exit;

    ## either all of the final jobs in the WF are done (no errors)
    #  or any of them exit.  run the ended handler
    my $dep_expr = ' -w "(' .
        join(' && ', @d) . ') || (' . 
        join(' || ', @e) . ')"';

    my $cmd = sprintf("bsub -H -u \"eclark\@genome.wustl.edu\" -Q 5 -q %s %s %s workflow ns internal end %s",
        'long', $job_group, $dep_expr, $id);

    $self->status_message("lsf\$ $cmd\n");
    my $bsub_output = `$cmd`;

    $self->status_message($bsub_output);

    if ( $bsub_output =~ /^Job <(\d+)> is submitted to queue <(\w+)>\./ ) {

        return $1;
    } else {
        die 'cant launch!';
    }
}

sub validate_workflow {
    my ( $self, $w ) = @_;

    unless ( $w->is_valid ) {
        my @errors = $w->validate;
        unless ( @errors == 0 ) {
            $self->error_message("Cannot execute invalid workflow");
            return;
        }
    }
    return 1;
}

my $xt_set = 0;
my $xt;
sub xauth_token {
    return $xt if $xt_set;
    my ($self) = shift;

    my $token;

    if ($ENV{DISPLAY} =~ /^([^:]*):(\d+)(\.\d+)*$/) {
        my $host = $1;
        my $num = $2;

        if ($host eq '') {
            $host = `uname -n`;
            chomp $host;
        }

        my $re = "$host(/unix)*:$num";

        open XA, 'xauth list |';
        while (my $line = <XA>) {
            chomp $line;
            my @e = split(/\s+/, $line);

            if ($e[0] =~ /$re/) {
                $token = $e[2] if !$token || length($e[2]) < length($token);
            }
        }
        close XA;

        if ($token =~ /unix:/) {
            $xt_set = 1;
            $self->error_message("Unix sockets for X11 not supported for this debugging feature.");
            $self->error_message("I know you're probably forwarding with ssh but there's no good way to handle that yet");
            return;
        }

        $xt = $token;
        $xt_set = 1;

        return $token;
    } else {
        $self->error_message("cant parse DISPLAY env");
        $xt_set = 1;
        return;
    }
}

1;
