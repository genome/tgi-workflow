package Cord::Config;

our $primary_schema_name = 'Local';
our $primary_data_source = 'Cord::DataSource::' . $primary_schema_name;

1;
