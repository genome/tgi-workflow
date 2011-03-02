
package Workflow::Operation::InstanceExecution;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution {
    id_by => [
        execution_id =>
          { is => 'NUMBER', len => 11, column_name => 'WORKFLOW_EXECUTION_ID' },
    ],
    table_name  => 'WORKFLOW_INSTANCE_EXECUTION',
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
    has         => [
        instance_id =>
          { is => 'NUMBER', len => 11, column_name => 'WORKFLOW_INSTANCE_ID' },
        operation_instance =>
          { is => 'Workflow::Operation::Instance', id_by => 'instance_id' },
        status       => { is => 'VARCHAR2',  len => 15, value       => 'new' },
        start_time   => { is => 'TIMESTAMP', len => 20, is_optional => 1 },
        end_time     => { is => 'TIMESTAMP', len => 20, is_optional => 1 },
        elapsed_time => {
            calculate_from => [ 'start_time', 'end_time' ],
            calculate      => q{
                return unless $start_time;
                my $diff;
                if ($end_time) {
                    $diff = Workflow::Time->datetime_to_time($end_time) - Workflow::Time->datetime_to_time($start_time);
                } else {
                    $diff = time - Workflow::Time->datetime_to_time($start_time);
                }

                my $seconds = $diff;
                my $days = int($seconds/(24*60*60));
                $seconds -= $days*24*60*60;
                my $hours = int($seconds/(60*60));
                $seconds -= $hours*60*60;
                my $minutes = int($seconds/60);
                $seconds -= $minutes*60;

                my $formatted_time;
                if ($days) {
                    $formatted_time = sprintf("%d:%02d:%02d:%02d",$days,$hours,$minutes,$seconds);
                } elsif ($hours) {
                    $formatted_time = sprintf("%02d:%02d:%02d",$hours,$minutes,$seconds);
                } elsif ($minutes) {
                    $formatted_time = sprintf("%02d:%02d",$minutes,$seconds);
                } else {
                    $formatted_time = sprintf("%02d:%02d",$minutes,$seconds);
                }

                return $formatted_time;
            }
        },
        exit_code  => { is => 'NUMBER',   len => 5,   is_optional => 1 },
        stdout     => { is => 'VARCHAR2', len => 255, is_optional => 1 },
        stderr     => { is => 'VARCHAR2', len => 255, is_optional => 1 },
        is_done    => { is => 'NUMBER',   len => 2,   is_optional => 1 },
        is_running => { is => 'NUMBER',   len => 2,   is_optional => 1 },
        dispatch_identifier => {
            is          => 'VARCHAR2',
            len         => 10,
            column_name => 'DISPATCH_ID',
            is_optional => 1
        },
        cpu_time      => { is => 'NUMBER',   len => 11, is_optional => 1 },
        max_threads   => { is => 'NUMBER',   len => 4,  is_optional => 1 },
        max_swap      => { is => 'NUMBER',   len => 10, is_optional => 1 },
        max_processes => { is => 'NUMBER',   len => 4,  is_optional => 1 },
        max_memory    => { is => 'NUMBER',   len => 10, is_optional => 1 },
        user_name     => { is => 'VARCHAR2', len => 20, is_optional => 1 },
        debug_mode    => {
            is            => 'Boolean',
            default_value => 0,
            is_transient  => 1,
            is_optional   => 1
        },
        errors => {
            is            => 'Workflow::Operation::InstanceExecution::Error',
            is_many       => 1,
            reverse_id_by => 'execution',
            is_optional   => 1
        },
        child_instances => {
            doc =>
'instances that were started by code called during this execution',
            is            => 'Workflow::Operation::Instance',
            is_many       => 1,
            reverse_id_by => 'parent_execution'
        },
        metrics => {
            is         => 'Workflow::Operation::InstanceExecution::Metric',
            is_many    => 1,
            reverse_as => 'instance_execution'
        }
    ]
};

sub create {
    my $class = shift;
    my $self  = $class->SUPER::create(@_);

    $self->fix_logs;
    $self->user_name( scalar getpwuid $< );

    return $self;
}

sub fix_logs {
    my $self = shift;

    if ( my $out = $self->operation_instance->out_log_file ) {
        $self->stdout($out);
    }
    if ( my $err = $self->operation_instance->err_log_file ) {
        $self->stderr($err);
    }

    if ( !$self->stdout && !$self->stderr ) {
        if ( $self->operation_instance->operation_type->can('stdout_log') ) {
            $self->stdout(
                $self->operation_instance->operation_type->stdout_log );
        }
        if ( $self->operation_instance->operation_type->can('stderr_log') ) {
            $self->stderr(
                $self->operation_instance->operation_type->stderr_log );
        }
    }
}

sub set_metric {
    my ( $self, $name, $value ) = @_;

    if ( defined $name ) {
        my $metric = $self->metrics( name => $name );
        if ( defined $metric ) {
            $metric->value($value);
        } else {
            $metric = $self->add_metric( name => $name, value => $value );
        }
        return $metric;
    }
}

sub get_metric {
    my ( $self, $name ) = @_;
    my $metric = $self->metrics( name => $name );
    return $metric->value if $metric;
    return;
}

1;
