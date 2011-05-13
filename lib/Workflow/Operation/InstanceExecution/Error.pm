
package Workflow::Operation::InstanceExecution::Error;

use strict;
use warnings;

class Workflow::Operation::InstanceExecution::Error {
    attributes_have => [
        copy_on_create => { 
            is => 'String',
            is_optional => 1
        }
    ],
    has_optional => [
        # Real properties of this class
        execution => {
            is => 'Workflow::Operation::InstanceExecution',
            id_by => 'execution_id'
        },
        error => {
            is => 'String',
            is_optional => 1
        },
        # Calculated Properties
        operation_instance => { 
            is => 'Workflow::Operation::Instance', 
            id_by => 'instance_id' 
        },
        # Next two properties must be run after copy_on_create's are done
        path_name => {
            is_constant => 1,
            calculate => q{
                return $self->_build_path_string;
            }
        },
        name => {
            is_constant => 1,
            calculate => q{
                return $self->operation_instance->operation->name;
            }
        },
        # Denormalized from other places, helps the server return usable error 
        # information across processes      
        instance_id => {
            copy_on_create => 'execution'
        },
        status => { 
            copy_on_create => 'execution'
        },
        start_time => { 
            copy_on_create => 'execution'    
        },
        end_time => { 
            copy_on_create => 'execution'
        },
        exit_code => { 
            copy_on_create => 'execution'
        },
        stdout => { 
            copy_on_create => 'execution'        
        },
        stderr => { 
            copy_on_create => 'execution'        
        },
        is_done => {
            copy_on_create => 'execution'
        },
        is_running => {
            copy_on_create => 'execution'
        },
        dispatch_identifier => {
            copy_on_create => 'execution'
        }
    ]
};

our @observers = (
    __PACKAGE__->add_observer(
        aspect => 'create',
        callback => sub {
            my $self = shift;

            my $class_meta = $self->__meta__;
            my @property_meta = $class_meta->all_property_metas();
            
            foreach my $property (grep { defined $_->{copy_on_create} } @property_meta) {
                my $property_name = $property->property_name;
                if (exists $property->{copy_on_create}) {
                    my $copy_from = $property->{copy_on_create};

                    my $intermediate = $self->$copy_from;
                    if (defined $intermediate) {
                        $self->$property_name( $intermediate->$property_name );
                    } else {
                        $self->$property_name(undef);
                    }
                }
            }
            foreach my $property_name (
                map { 
                    $_->property_name 
                } grep { 
                    exists $_->{calculate} && $_->is_constant 
                } @property_meta
            ) {
                # properties like this get memoized by UR the first time you call them
                $self->$property_name;
            }
        }
    )
);

# the calling mechanics of this function are stupid because UR runs calculated 
# properties in the UR::Object::Type package
sub _build_path_string {
    my $self = shift;
    my $instance = $self ? $self->operation_instance : shift;
    
    my $path_string = $instance->name;
    if ($instance->parent_instance) {
        $path_string = _build_path_string(undef,$instance->parent_instance) . '/' . $path_string;
    }

    return $path_string
}

1;
