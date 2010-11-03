
package Cord::Operation;

use strict;
use warnings;
use XML::Simple;

class Cord::Operation {
    has => [
        name => { is => 'Text' },
        workflow_model => { is => 'Cord::Operation', id_by => 'workflow_model_id', is_optional => 1 },
        operation_type => { is => 'Cord::OperationType', id_by => 'workflow_operationtype_id' },
        is_valid => { is => 'Boolean', default_value=>0, doc => 'Flag set when validate has run' },
        executor => { is => 'Cord::Executor', id_by => 'workflow_executor_id', is_optional => 1 },
        parallel_by => { is => 'String', is_optional=>1 },
        log_dir => { is => 'String', is_optional =>1 },
        filename => { is => 'String', is_optional => 1 },
        notify_url => { is => 'String', is_optional => 1, doc => 'URL that will be sent a GET request when any sub-status changes in this Workflow or Operation, multiple urls may be seperated by spaces' }
    ]
};

sub dependent_operations {
    my $self = shift;
    
    my %operations = map {
        $_->right_operation->id => $_->right_operation
    } Cord::Link->get(left_operation => $self);
    
    return values %operations;
}

sub depended_on_by {
    my $self = shift;
    
    my %operations = map {
        $_->left_operation->id => $_->left_operation
    } Cord::Link->get(right_operation => $self);
    
    return values %operations;
}

sub create {
    my $class = shift;
    my $self = $class->SUPER::create(@_);

    if (!$self->workflow_model && !$self->executor) {
        $self->executor(Cord::Executor::SerialDeferred->get);
    }

    return $self;
}

sub create_from_xml {
    my ($class, $filename) = @_;

    my $struct = XMLin($filename, KeyAttr=>[], ForceArray=>[qw/operation property inputproperty outputproperty link output/]);
    my $self = $class->create_from_xml_simple_structure($struct,filename=>$filename);

    return $self;
}

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my $self;

    ## i dont like this at all
    ## delegate sub-models
    if ($class eq __PACKAGE__ && (exists $struct->{operationtype} && $struct->{operationtype}->{typeClass} eq 'Cord::OperationType::Model' || $struct->{workflowFile})) {

        $self = Cord::Model->create_from_xml_simple_structure($struct,%params);
    } else {
        $params{parallel_by} = $struct->{parallelBy} if $struct->{parallelBy};
        $params{log_dir} = $struct->{logDir} if $struct->{logDir};
        $params{notify_url} = $struct->{notifyUrl} if $struct->{notifyUrl};

        if (exists $params{log_dir} && defined $params{log_dir}) {
            if ($params{log_dir}) {
                if ($params{log_dir} !~ /^\/gsc/) {
                    die "log directory not on a valid network volume for lsf: $params{log_dir}\n";
                }
            } else {
                die "log directory does not exist: $params{log_dir}\n";
            }
        }
        

        my $optype = Cord::OperationType->create_from_xml_simple_structure($struct->{operationtype});
        $self = $class->create(
            name => $struct->{name},
            operation_type => $optype,
            %params
        );
    }

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {
        name => $self->name,
        operationtype => $self->operation_type->as_xml_simple_structure
    };

    $struct->{logDir} = $self->log_dir if ($self->log_dir);
    $struct->{parallelBy} = $self->parallel_by if ($self->parallel_by);
    $struct->{notifyUrl} = $self->notify_url if ($self->notify_url);

    if (!$self->workflow_model) {
        $struct->{executor} = $self->executor->class;
    }

    return $struct;
}

sub save_to_xml {
    my $self = shift;
    my %args = @_;

    return XMLout($self->as_xml_simple_structure, KeyAttr=>[], RootName=>'operation', XMLDecl=>1, %args);
}

sub set_all_executor {
    my ($self,$exec) = @_;

    $self->executor($exec);
}

sub validate {
    my ($self) = @_;
    
    $self->is_valid(1);
    return ();
}

sub operations_in_series {
    my $self = shift;

    return ($self);
}

sub execute {
    my $self = shift;
    my %params = (@_);

    unless ($self->is_valid) {
        my @errors = $self->validate;
        unless (@errors == 0) {
            die 'cannot execute invalid workflow';
        }
    }
    
    {
        my %ikeys = map { $_ => 1 } keys %{ $params{input} };
        foreach my $k (@{ $self->operation_type->input_properties }) {
            delete $ikeys{$k} if exists $ikeys{$k};
        }

        if (scalar keys %ikeys) {
            Carp::croak('execute: Extra inputs provided: ' . join (', ', keys %ikeys));
            return;
        }
    }

    my $operation_instance = Cord::Operation::Instance->create(
        operation => $self,
        output_cb => $params{output_cb},
        error_cb => $params{error_cb}
    );
    $operation_instance->input($params{input} || {});
    $operation_instance->output({});

    $operation_instance->execute;

    return $operation_instance;
}

sub wait {
    my $self = shift;
    
    $self->executor->wait($self);
}

sub detach {
    my $self = shift;
    
    $self->executor->detach($self);
}

1;
