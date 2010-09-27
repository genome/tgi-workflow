package Workflow::Config;

our $primary_schema_name = 'InstanceSchema';
our $primary_data_source = 'Workflow::DataSource::' . $primary_schema_name;

1;
