use strict;
use warnings;
use File::Temp;

package Workflow::DataSource::InstanceSchemaPostgres;

use Workflow;

class Workflow::DataSource::InstanceSchemaPostgres {
    is => ['UR::DataSource::Pg'],
	has_constant => [
	        server => { default_value => 'dbname=genome;host=gms-postgres' },
	        login => { default_value => 'genome' },
	        auth => { default_value => 'TGIlab' },
	        owner => { default_value => 'workflow' },
	    ],
};

sub _ds_tag {
    'Workflow::DataSource::InstanceSchemaPostgres';
}

sub _sync_database {
    my $self = shift;
    my %params = @_;

    # Need to remove all commit observers, they will be fired during commit and that's no good!
    my @observers = UR::Observer->get();
    for my $observer (@observers) {
        $observer->delete;
    }

    # Need to update all classes that have been changed (and all of their parent
    # classes) to use the postgres datasource instead of Oracle.
    my %classes = map { $_->class => 1 } @{$params{changed_objects}};
    for my $class (sort keys %classes) {
        my $meta = UR::Object::Type->get($class);
        next unless $meta;
        my @metas = ($meta, $meta->ancestry_class_metas);
        for my $meta (@metas) {

            # If the object has been deleted and we're dealing with the Ghost, need to find the non-Ghost class
            # and add that to the list of metas we need to update. Otherwise, that class won't get updated to use
            # postgres and an error will occur.
            if ($meta->class_name =~ /::Ghost$/) {
                my $non_ghost_class = $meta->class_name;
                $non_ghost_class =~ s/::Ghost$//;
                my $non_ghost_meta = UR::Object::Type->get($non_ghost_class);
                if ($non_ghost_meta) {
                    push @metas, $non_ghost_meta;
					
					print "Working on $non_ghost_meta\n"
                }
                else {
                    Carp::confess "Could not find meta object for non-ghost class $non_ghost_class!";
                }
            }

            if (defined $meta->data_source and $meta->data_source->id eq 'Workflow::DataSource::InstanceSchema') {
                $meta->data_source($self->_ds_tag);

                # Columns are stored directly on the meta object as an optimization, need to be updated
                # in addition to table/column objects.
                my (undef, $cols) = @{$meta->{'_all_properties_columns'}};
                $_ = lc $_ foreach (@$cols);

                if (defined $meta->table_name) {
                    my $oracle_table = $meta->table_name;
                    my $postgres_table = $self->postgres_table_name_for_oracle_table($oracle_table);
                    unless ($postgres_table) {
                        Carp::confess "Could not find postgres equivalent for oracle table $oracle_table while working on class $class";
                    }
                    $meta->table_name($postgres_table);

                    my @properties = $meta->all_property_metas;
                    for my $property (@properties) {
                        next unless $property->column_name;
                        $property->column_name(lc $property->column_name);
                    }
                }
            }
        }
    }

    # Update meta datasource to point to an empty file so we don't get failures due to not being
    # able to find column/table meta data.
    my $temp_file_fh = File::Temp->new;
    my $temp_file = $temp_file_fh->filename;
    $temp_file_fh->close;

    my $meta_ds = Workflow::DataSource::Meta->_singleton_object;
    $meta_ds->get_default_handle->disconnect;
    $meta_ds->server($temp_file);
    
    return $self->SUPER::_sync_database(@_);
}
    
sub postgres_table_name_for_oracle_table {
    my $self = shift;
    my $oracle_table = shift;
    return unless $oracle_table;
    my %mapping = $self->oracle_to_postgres_table_mapping;
    return $mapping{lc $oracle_table};
}

sub oracle_to_postgres_table_mapping {
    return (
        'workflow_execution_metric' => 'workflow.execution_metric',
        'workflow_instance' => 'workflow.instance',
        'workflow_instance_execution' => 'workflow.instance_execution',
        'workflow_plan' => 'workflow.plan',
        'workflow_service' => 'workflow.service',
    );
}
1;
