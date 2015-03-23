
package Workflow::OperationType::Command;

use strict;
use warnings;

use Time::HiRes;
use Workflow;
use Workflow::Instrumentation qw(timing);

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
    Carp::confess("this should never be called!");
}

sub resource_for_instance {
    my ($self, $instance) = @_;
    my $command_class_name = $self->command_class_name;
    my $inputs = $instance->input;
    my $requirements;
    if ($command_class_name->can('resolve_resource_requirements')) {
        $requirements = $command_class_name->resolve_resource_requirements($inputs);
        if ($requirements and not ref($requirements)) {
            my $resource_obj = Workflow::LsfParser->get_resource_from_lsf_resource($requirements);
            unless ($resource_obj) {
                die "cannot convert $requirements into a resource object";
            }
            $requirements = $resource_obj;
        }
    }
    else {
        $requirements = Workflow::LsfParser->get_resource_from_lsf_resource($self->lsf_resource);
    }
    return $requirements;
}

sub initialize {
    my $self = shift;
    my $command = $self->command_class_name;

    my $class_meta = $self->_get_command_meta($command);

    my @property_meta = $class_meta->all_property_metas();
    # Know which properties are ids for other properties and make them optional.
    # It would be more correct to know that one of N properties must be specified
    # but what really should happen is that the command should construct
    # _before_ dispatch, and dispatch only after construction, so you can
    # fully handle things like a smart constructor which sets odd properties
    # according to arbitrary logic.  Bottom line: testing params pre-construct
    # is not what this really should be doing.
    my %id_by;
    for my $p (@property_meta) {
        my $id_by = $p->id_by;
        next if not $id_by;
        my @id_by;
        if (ref($id_by)) {
            @id_by = @$id_by;
        }
        else {
            @id_by = ($id_by)
        }
        for my $id (@id_by) {
            $id_by{$id} = $p;
        }
    }

    foreach my $type (qw/input output/) {
        my $my_method = $type . '_properties';
        unless ($self->$my_method) {
            my @property_meta_of_type = grep {
                if ($type eq 'input') {
                    (defined $_->{'is_input'} && $_->{'is_input'})
                    ||
                    ($_->can('is_input') && $_->is_input)
                    ||
                    ( ((defined $_->{'is_param'} && $_->{'is_param'})
                        || ($_->can('is_param') && $_->is_param))
                        && ! ($_->property_name =~ /^(lsf_queue|lsf_resource)$/) )
                }
                elsif ($type eq 'output') {
                    defined $_->{'is_output'} && $_->{'is_output'}
                    ||
                    ($_->can('is_output') && $_->is_output)
                }
            } @property_meta;

            my @props = map { $_->property_name } @property_meta_of_type;
            $self->{$my_method} = $self->{'db_committed'}{$my_method} = \@props;

            if ($type eq 'input') {
                my @opt_input;
                for my $pm (@property_meta_of_type) {
                    if ($pm->default_value || $pm->is_optional || $pm->id_by || $pm->via || $id_by{$pm->property_name} || $pm->{is_param}) {
                        push @opt_input, $pm->property_name;
                    }
                }
                $self->{optional_input_properties} = $self->{'db_committed'}{optional_input_properties} = \@opt_input;
            }
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

sub _get_command_meta {
    my ($self, $command) = @_;

    # This function has significant side effects.

    # If you try to use a UR object without first using that object's
    # namespace, then it appears you will never be able to properly load that
    # object even if you load the namespace later.
    # Therefore, we must first try to load any UR namespaces, and only then try
    # to load the particular command object.

    my $failed_to_use_namespace;
    my $namespace = (split(/::/,$command))[0];
    if (defined $namespace && !exists $INC{"$namespace.pm"}) {
        eval "use " . $namespace;
        if ($@) {
            $failed_to_use_namespace = $@;
        }
    }

    my $failed_to_use_comand;
    eval "use $command";
    if ($@) {
        $failed_to_use_comand = $@;
    }

    if ($failed_to_use_comand && $failed_to_use_namespace) {
        Carp::confess(sprintf(
                "Failed to load command with direct use and via namespace.\n"
                . "Error message from use: %s"
                . "\nError message from namespace: %s",
                $failed_to_use_comand,
                $failed_to_use_namespace));
    }

    my $class_meta = eval { $command->__meta__ };
    if($@ or not $class_meta) {
        Carp::confess(sprintf(
                "Could not find __meta__ for command '%s'.  This may "
                . "indicate a partially (incompletely) loaded class.",
                $command));
    }

    return $class_meta;
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

    my $time_before = Time::HiRes::time();
    my $output = $self->call('shortcut', @_);
    my $time_after = Time::HiRes::time();
    timing("workflow.operation_type.command.shortcut", 1000.0 * ($time_after-$time_before));

    return $output;
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
    my $class_meta = $command_name->__meta__;

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
            #print "Reloaded $old_value as $value\n";
        }
        my $pmeta = $class_meta->property($key);
        unless ($pmeta) {
            die "property $key not found on class $command_name";
        }
        # this is where we would handle sets, etc, as well...
        if (ref($value) and ref($value) eq 'ARRAY') {
            if (not $pmeta->is_many and not $pmeta->data_type eq 'ARRAY') {
                # convert many to one if possible
                if (@$value > 1) {
                    die "multiple values for $key passed to $command_name!";
                }
                elsif (@$value == 1) {
                    $properties{$key} = $value->[0];
                }
                else {
                    $properties{$key} = undef;
                }
            }
        }
        else {
            if ($pmeta->is_many) {
                # convert one to a one-item list of many
                $properties{$key} = [$value];
            }
        }
    }

    if ($type eq 'shortcut' && !$command_name->can('_shortcut_body')) {
        return;
    }

    my @errors = ();

    # override the error callback
    my $error_cb = UR::ModuleBase->message_callback('error');
    UR::ModuleBase->message_callback(
        'error',
        sub {
            my ($error, $self) = @_;
            my $package_name = $error->package_name || 'UnknownPackage';
            my $text = $error->text || 'No error text.';
            push @errors, $package_name . ': ' . $text;
        }
    );
    # when this goes out of scope or is otherwise undefined the error messaging will reset
    # this ensures that if an exception is thrown we clean up after ourselves still
    my $sentry = UR::Util::on_destroy sub { UR::ModuleBase->message_callback('error',$error_cb) };

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

    @errors = map { "$command_name: Error " . $_->desc } $command->__errors__;
    if (@errors) {
        die join("\n",@errors);
    }

    $command->dump_status_messages(1);
    $command->dump_warning_messages(1);
    $command->dump_error_messages(1);
    $command->dump_debug_messages(0);
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
            unshift @errors, $command_name . " failed to return a positive true value (rv = " . $display_retvalue . ")";
            die join("\n",@errors);
        }
    }


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
