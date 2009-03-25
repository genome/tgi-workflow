package Workflow::Service;

use strict;
use warnings;
use Sys::Hostname ();

use Workflow;
class Workflow::Service {
    type_name => 'workflow service',
    table_name => 'WORKFLOW_SERVICE',
    id_by => [
        hostname   => { is => 'VARCHAR2', len => 255 },
        username   => { is => 'VARCHAR2', len => 10 },
        process_id => { is => 'NUMBER', len => 10 },
        port       => { is => 'NUMBER', len => 7 },
        start_time => { is => 'TIMESTAMP', len => 20 },
    ],
    schema_name => 'InstanceSchema',
    data_source => 'Workflow::DataSource::InstanceSchema',
};

sub create {
    my $class = shift;
    my %args = (@_);
    
    my $self = $class->SUPER::create(
        hostname => Sys::Hostname::hostname(),
        username => (getpwuid($<))[0],
        process_id => $$,
        port => $args{port} || $Workflow::Server::UR::port_number,
        start_time => UR::Time->now
    );

    return $self;
}

1;
