
package Workflow::OperationType::Command;

use strict;
use warnings;

class Workflow::OperationType::Command {
    isa => [ 'UR::Value', 'Workflow::OperationType' ],
    is_transactional => 0,
    id_by => [ 'command_class_name' ],
    has => [
        command_class_name => { is => 'String' },
        lsf_resource => { is => 'String', is_optional=>1 },
        lsf_queue => { is => 'String', is_optional=>1 },
        lsf_project => { is => 'String', is_optional=>1 },
        job => { is => 'Workflow::Dispatcher::Job', is_optional => 1 },
    ],
};

__PACKAGE__->add_observer(
    aspect => 'load',
    callback => sub {
        my $self = shift;

        $self->initialize;
});

sub create {
    my $cls = shift;
    my $self = $cls->get(@_);
    return $self;
}

sub resource {
    my $self = shift;
    return Workflow::LsfParser->get_resource_from_lsf_resource($self->lsf_resource);
}

sub initialize {
    my $self = shift;
    my $command = $self->command_class_name;

    # Old-style definations call a function after setting up the class

    my $namespace = (split(/::/,$command))[0];
    if (defined $namespace && !exists $INC{"$namespace.pm"}){
        eval "use " . $namespace;
        if ($@) {
            die $@;
        }
    }

    my $class_meta = $command->__meta__;
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
                    ($_->default_value || $_->is_optional) &&
                    defined $_->{'is_input'} && $_->{'is_input'}
                } @property_meta;

                $self->{optional_input_properties} = $self->{'db_committed'}{optional_input_properties} = \@opt_input;
            }
        
            $self->{$my_method} = $self->{'db_committed'}{$my_method} = \@props;
        }
    }

    my @params = qw/lsf_resource lsf_queue lsf_project/;
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
    $self->lsf_project(delete $struct->{lsfProject}) if (exists $struct->{lsfProject});
    # these warnings are useful while tracking lsf resource origins, but will be removed
    # when that project is complete.
    # warn "Create from xml lsf_resource " . ($self->lsf_resource || "undefined") . "\n";
    # warn "lsf_queue " . ($self->lsf_queue || "undefined") . "\n";
    # warn "lsf_project " . ($self->lsf_project || "undefined") . "\n";
    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;
    $struct->{commandClass} = $self->command_class_name;

    #warn "Simple XML Struct lsf_resource: " . ($self->lsf_resource || "undefined") . "\n";
    #warn "queue: " . ($self->lsf_queue || "undefined") . "\n";
    #warn "project: " . ($self->lsf_project || "undefined") . "\n";

    $struct->{lsfResource} = $self->lsf_resource if ($self->lsf_resource);
    $struct->{lsfQueue} = $self->lsf_queue if($self->lsf_queue);
    $struct->{lsfProject} = $self->lsf_project if($self->lsf_project);

    # command classes have theirs defined in source code
    delete $struct->{inputproperty};
    delete $struct->{outputproperty};

    return $struct;
}

sub create_from_command {
    my ($class, $command_class, $options) = @_;

    my $self = $class->get($command_class);

    unless ($self) {
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
    $self->input_properties(\@valid_inputs);
    $self->output_properties(\@valid_outputs);
    $self->lsf_resource($options->{lsf_resource});
    $self->lsf_queue($options->{lsf_queue});

    return $self;
}

sub _validate_property {
    my ($self, $class, $direction, $name) = @_;

    my $meta = $class->__meta__->property_meta_for_name($name);

    if (($direction ne 'output' && $meta->property_name eq 'result') ||
        ($direction ne 'output' && $meta->is_calculated)) {
        return 0;
    } else {
        return 1;
    }
}

sub shortcut {
    my $self = shift;
    $self->call('shortcut', @_);
}

 sub execute {
    my $self = shift;
    $self->call('execute', @_);
}

# delegate to wrapped command class
sub call {
    my $self = shift;
    my $type = shift;

    unless ($type eq 'shortcut' || $type eq 'execute') {
        die 'invalid type: ' . $type;
    }
    my %properties = @_;

    my $command_name = $self->command_class_name;

    foreach my $key (keys %properties) {
        my $value = $properties{$key};
        if ((defined $value) and (Scalar::Util::blessed $value) 
                and $value->isa('UR::Object')){
            my $id = $value->id;
            my $class_name = $value->class;
            my $old_value = $value;
            $value = $class_name->get($id);
            unless($value) {
                die "Starting command $command_name: could not get object of class $class_name with id $id for property $key";
            }
            $properties{$key} = $value;
            print "Reloaded $old_value as $value\n";
        }
    }

    if ($type eq 'shortcut' && !$command_name->can('_shortcut_body')) {
        return;
    }

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
    #warn "Dispatching via OperationType::Command " . $command . "\n";
    #warn "Our LSF settings: " . ($self->lsf_queue || "undefined") . "\n";
    #warn "resource : " . ($self->lsf_resource || "undefined") . "\n";
    #warn "project : " . ($self->lsf_project || "undefined") . "\n";

    my $retvalue;
    if ($type eq 'shortcut') {
        unless ($command->can('shortcut')) {
            die ref($command) . ' has no method shortcut; ' .
                'dying so execute can run on another host';
        }
        $retvalue = $command->shortcut();
    } elsif ($type eq 'execute') {
        $retvalue = $command->execute();
    }

    unless (defined $retvalue && $retvalue && $retvalue > 0) {
        my $display_retvalue = (defined $retvalue ? $retvalue : 'undef');
        if($type eq 'shortcut') {
            $command->status_message("Unable to shortcut (rv = " . $display_retvalue . ").");
            return;
        } else {
            die $command_name . " failed to return a positive true value (rv = " . $display_retvalue . ")";
        }
    }

    UR::ModuleBase->message_callback('error',$error_cb);

    my %outputs = ();
    foreach my $output_property (@{ $self->output_properties }) {
        if ($command->__meta__->property($output_property)->is_many) {
            $outputs{$output_property} = [$command->$output_property];
        } else {
            $outputs{$output_property} = $command->$output_property;
        }
    }

    return \%outputs;
}

1;
