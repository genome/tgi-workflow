
package Workflow::OperationType::Command;

use strict;
use warnings;

class Workflow::OperationType::Command {
    isa => 'Workflow::OperationType',
    is_transactional => 0,
    id_by => [ 'command_class_name' ],
    has => [
        command_class_name => { is => 'String' },
        lsf_resource => { is => 'String', is_optional=>1 },
        lsf_queue => { is => 'String', is_optional=>1 },
    ],
};

sub get {
    my $class = shift;
    return $class->SUPER::get( @_ ) || $class->create ( @_ );
}

sub create {
    my $class = shift;
    my $params = $class->preprocess_params(@_);
    
    die 'missing command class' unless $params->{command_class_name};

    # Old-style definations call a function after setting up the class
    {
        eval "use " . $params->{command_class_name};
        if ($@) {
            die $@;
        }

        # see if it got created
        my $self = $class->SUPER::get($params->{command_class_name});
        return $self if $self;
    }
    
    my $self = $class->SUPER::create(@_);
    my $command = $self->command_class_name;
    

    my $class_meta = $command->get_class_object;
    die 'invalid command class' unless $class_meta;

    my @property_meta = $class_meta->all_property_metas();

    foreach my $type (qw/input output/) {
        my $my_method = $type . '_properties';
        unless ($self->$my_method) {
            my @props = map {
                $_->property_name
            } grep { 
                defined $_->{'is_' . $type} && $_->{'is_' . $type}
            } @property_meta;

            if ($type eq 'input') {
                my @opt_input = map {
                    $_->property_name
                } grep {
                    $_->is_optional &&
                    defined $_->{'is_input'} && $_->{'is_input'}
                } @property_meta;

                $self->optional_input_properties(\@opt_input);
            }
        
            $self->$my_method(\@props);
        }
    }

    my @params = qw/lsf_resource lsf_queue/;
    foreach my $param_name (@params) {
        unless ($self->$param_name) {
            my $prop = $class_meta->property_meta_for_name($param_name);

            if ($prop && $prop->{is_param}) {
                if ($prop->default_value) {
                    $self->$param_name($prop->default_value);
                } else {
                    warn "$command property $param_name should have a default value if it is a parameter.  to be fixed in a future workflow version";
                }
            }
        }
    }
    
    return $self;
}

sub create_from_xml_simple_structure {
    my ($class, $struct) = @_;

    my $command = delete $struct->{commandClass};
    my $self = $class->get($command);
    
    $self->lsf_resource(delete $struct->{lsfResource}) if (exists $struct->{lsfResource});
    $self->lsf_queue(delete $struct->{lsfQueue}) if (exists $struct->{lsfQueue});

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{commandClass} = $self->command_class_name;

    $struct->{lsfResource} = $self->lsf_resource if ($self->lsf_resource);
    $struct->{lsfQueue} = $self->lsf_queue if($self->lsf_queue);

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub create_from_command {
    my ($self, $command_class, $options) = @_;

    unless ($command_class->get_class_object) {
        die 'invalid command class';
    }

    unless ($options->{input} && $options->{output}) {
        die 'invalid input/output definition';
    }

    my @valid_inputs = grep {
        $self->_validate_property( $command_class, input => $_ )
    } @{ $options->{input} };

    my @valid_outputs = grep {
        $self->_validate_property( $command_class, output => $_ )
    } @{ $options->{output} }, 'result';

    return $self->SUPER::create(
        input_properties => \@valid_inputs,
        output_properties => \@valid_outputs,
        command_class_name => $command_class,
        lsf_resource => $options->{lsf_resource},
        lsf_queue => $options->{lsf_queue},
    );
}

sub _validate_property {
    my ($self, $class, $direction, $name) = @_;

    my $meta = $class->get_class_object->property_meta_for_name($name);

    if (($direction ne 'output' && $meta->property_name eq 'result') ||
        ($direction ne 'output' && $meta->is_calculated)) {
        return 0;
    } else {
        return 1;
    }
}

# delegate to wrapped command class
sub execute {
    my $self = shift;
    my %properties = @_;

    my $command_name = $self->command_class_name;

    my @errors = ();

    my $error_cb = UR::ModuleBase->message_callback('error');
    UR::ModuleBase->message_callback(
        'error',
        sub {
            my ($error, $self) = @_;
            
            push @errors, $error->package_name . ': ' . $error->text;
        }
    );

    $command_name->dump_status_messages(1);
    $command_name->dump_warning_messages(1);
    $command_name->dump_error_messages(1);
    $command_name->dump_debug_messages(0);

    my $command = $command_name->create(%properties);

    if ($Workflow::DEBUG_GLOBAL) {
        if (UNIVERSAL::can('Devel::ptkdb','brkonsub')) {
            Devel::ptkdb::brkonsub($command_name . '::execute');
        } elsif (UNIVERSAL::can('DB','cmd_b_sub')) {
            DB::cmd_b_sub($command_name . '::execute');
        } else {
            $DB::single=2;
        }
    }

    if (!defined $command) {
        die "Undefined value returned from $command_name->create\n" . join("\n", @errors) . "\n";
    }

    $command_name->dump_status_messages(1);
    $command_name->dump_warning_messages(1);
    $command_name->dump_error_messages(1);
    $command_name->dump_debug_messages(0);

    my $retvalue = $command->execute;

    UR::ModuleBase->message_callback('error',$error_cb);

    my %outputs = ();
    foreach my $output_property (@{ $self->output_properties }) {
        $outputs{$output_property} = $command->$output_property;
    }

    return \%outputs;
}

1;
