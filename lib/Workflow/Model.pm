
package Workflow::Model;

use strict;
use warnings;
use GraphViz;
use XML::Simple;
use File::Basename;

use Workflow ();

class Workflow::Model {
    isa => 'Workflow::Operation',
    has => [
        operations => { is => 'Workflow::Operation', is_many => 1, reverse_id_by => 'workflow_model' },
        links => { is => 'Workflow::Link', is_many => 1 },
    ]
};

my $_add_operation_tmpl;
my $_create_model_input_tmpl;
sub create {
    my $class = shift;
    my %params = @_;

    my $optype = $params{operation_type};
    unless ($params{operation_type}) {
        $optype = Workflow::OperationType::Model->create(
            input_properties => delete($params{input_properties}) || [],
            optional_input_properties => delete($params{optional_input_properties}) || [],
            output_properties => delete($params{output_properties}) || []
        );

        $params{operation_type} = $optype;
    }

    my $self = $class->SUPER::create(%params);

    # The next few lines do the same work as add_operation(), but is optimized
    # to be fast
    $_create_model_input_tmpl ||= UR::BoolExpr::Template->resolve(
                                        'Workflow::OperationType::ModelInput',
                                        'id','input_properties','output_properties'
                                    )->get_normalized_template_equivalent();

    my $input_op_type_id = Workflow::OperationType::ModelInput->__meta__->autogenerate_new_object_id();
    my $input_op_type = UR::Context->create_entity('Workflow::OperationType::ModelInput',
                                                    $_create_model_input_tmpl->get_rule_for_values(
                                                            $input_op_type_id,
                                                            [],
                                                            $optype->input_properties,
                                                    ));
    $_add_operation_tmpl ||= UR::BoolExpr::Template->resolve(
                                            'Workflow::Operation',
                                            'id','name','workflow_model_id','workflow_operationtype_id'
                                        )->get_normalized_template_equivalent;

    my $input_op = UR::Context->create_entity('Workflow::Operation',
                                $_add_operation_tmpl->get_rule_for_values(
                                    Workflow::Operation->__meta__->autogenerate_new_object_id(),
                                    'input connector',
                                    $self->id,
                                    $input_op_type_id));
    $input_op->_post_create();

    my $output_op_type_id = Workflow::OperationType::ModelOutput->__meta__->autogenerate_new_object_id();
    my $output_op_type = UR::Context->create_entity('Workflow::OperationType::ModelOutput',
                                                    $_create_model_input_tmpl->get_rule_for_values(
                                                            $output_op_type_id,
                                                            $optype->output_properties,
                                                            []
                                                    ));

    my $output_op = UR::Context->create_entity('Workflow::Operation',
                                $_add_operation_tmpl->get_rule_for_values(
                                    Workflow::Operation->__meta__->autogenerate_new_object_id(),
                                    'output connector',
                                    $self->id,
                                    $output_op_type_id));
    $output_op->_post_create();

    return $self;
}

sub XOXOXcreate_from_xml {
    my ($class, $filename) = @_;

    my $struct = XMLin($filename, KeyAttr=>[], ForceArray=>[qw/operation property inputproperty outputproperty link/]);
    my $self = $class->create_from_xml_simple_structure($struct,filename=>$filename);

    return $self;
}

sub save_to_xml {
    my $self = shift;
    my %args = @_;

    return XMLout($self->as_xml_simple_structure, RootName=>'workflow', XMLDecl=>1, %args);
}

sub create_from_xml_simple_structure {
    my $class = shift;
    my $struct = shift;
    my %params = (@_);

    my $self;
    if ($struct->{workflowFile}) {
        my $file_basepath = dirname($params{workflow_model}->filename);

        $self = $class->create_from_xml($file_basepath . '/' . $struct->{workflowFile});
        $self->name($struct->{name});
        $self->workflow_model($params{workflow_model});
    } else {
        my $operations = delete $struct->{operation};
        my $links = delete $struct->{link};

        if (my $par = delete $struct->{parallelBy}) {
            $params{parallel_by} = $par;
        }

        if (my $executor_class = delete $struct->{executor}) {
            $params{executor} = $executor_class->get();
        }

        $self = $class->SUPER::create_from_xml_simple_structure($struct,%params);

        foreach my $op_struct (@$operations) {
            my $op = Workflow::Operation->create_from_xml_simple_structure($op_struct,workflow_model=>$self);
            if ($op->operation_type->isa('Workflow::OperationType::Model')) {
                $op->executor($params{executor}) if ($params{executor});
            }
        }

        foreach my $link_struct (@$links) {
            my $link = Workflow::Link->create_from_xml_simple_structure($link_struct,workflow_model=>$self);
        }
    }

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;

    $struct->{parallelBy} = $self->parallel_by if ($self->parallel_by);

    $struct->{operation} = [
        map {
            $_->as_xml_simple_structure
        } grep {
            $_->name ne 'input connector' && $_->name ne 'output connector'
        } $self->operations
    ];

    $struct->{link} = [
        map {
            $_->as_xml_simple_structure
        } $self->links
    ];

    return $struct;
}

sub get_input_connector {
    my $self = shift;

    my $input = Workflow::Operation->get(
        workflow_model => $self,
        name => 'input connector'
    );
    return $input;
}

sub get_output_connector {
    my $self = shift;

    my $output = Workflow::Operation->get(
        workflow_model => $self,
        name => 'output connector'
    );
    return $output;
}

## needs to be pulled into a viewer
sub graph {
    my $self = shift;

    my $g = GraphViz->new(
        overlap => 'compress',
        node => { shape => 'ellipse' },
    );

#    my $cluster = {
#        label => '-' . $self->name . '-',
#        style => 'filled',
#        fillcolor => 'lightgray'
#    };

    $self->add_gv_nodes($g); #,$cluster);

    return $g;
}
## needs to be pulled into a viewer
sub add_gv_nodes {
    my ($self, $g, $cluster) = @_;

    my @operations = $self->operations;
    my @links = $self->links;

    my %nodeports = ();
    my %remap_left_operation_ids = ();
    my %remap_right_operation_ids = ();
    foreach my $operation (@operations) {
        my $inputs = $operation->operation_type->input_properties;
        my $outputs = $operation->operation_type->output_properties;

        my $n = 0;
        $nodeports{$operation->id} = {};
        for (@{ $inputs }) {
            $nodeports{$operation->id}->{'IN ' . $_} = $n++;
        }
        $nodeports{$operation->id}->{'OPR' . $operation->id} = $n++;
        for (@{ $outputs }) {
            $nodeports{$operation->id}->{'OUT' . $_} = $n++;
        }

        ## percent symbols in front of the name cause graphviz to overload all the names i give it, fixing a bug

        $n = 0;

        if ($operation->isa('Workflow::Model')) {

            my $cluster = {
                label => '-' . $operation->name . '-',
                style => 'filled',
                fillcolor => 'lightgray'
            };

            my $op_nodeports = $operation->add_gv_nodes($g, $cluster);

            my $input_id = $operation->get_input_connector->id; 
            my $output_id = $operation->get_output_connector->id;

            $remap_left_operation_ids{$operation->id} = $output_id;
            $remap_right_operation_ids{$operation->id} = $input_id;

            foreach my $id ($input_id, $output_id) {
                $nodeports{$id} = {};
                while (my ($k,$v) = each(%{ $op_nodeports->{$id}})) {
                    if (substr($k,0,3) eq 'IN ') {
                        substr($k,0,3,'OUT');
                    } elsif (substr($k,0,3) eq 'OUT') {
                        substr($k,0,3,'IN ');
                    }
                    $nodeports{$id}->{$k} = $v;
                }
            }

        } else {
            $g->add_node(
                '%' . $operation->id, 
                color => 'black',
                fillcolor => 'lightblue2',
                style => 'filled',
                shape => 'record',
                constraint => 0,
                cluster => $cluster,
                label => '{' .
                    (@{ $inputs } ? '{' . join('|', map { '{<port' . $n++ . '>' . $_ . '}' } @{ $inputs }) . '}' : '') .
                    '|<port' . $n++ . '>' . $operation->name . '|' . 
                    (@{ $outputs } ? '{' . join('|', map { '{<port' . $n++ . '>' . $_ . '}' } @{ $outputs }) . '}' : ''). 
                '}',
            );
        }
    }
    foreach my $link (@links) {
        my $left_operation_id = $remap_left_operation_ids{$link->left_operation->id} || $link->left_operation->id;
        my $right_operation_id = $remap_right_operation_ids{$link->right_operation->id} || $link->right_operation->id;
        $g->add_edge(
            '%' . $left_operation_id, 
            '%' . $right_operation_id,
            from_port => $nodeports{$left_operation_id}->{'OUT' . $link->left_property}, 
            to_port => $nodeports{$right_operation_id}->{'IN ' . $link->right_property} ,
        );
    }

    return \%nodeports;
}

sub as_png {
    my $self = shift;
    return $self->graph->as_png(@_);
}

sub as_ps {
    my $self = shift;
    return $self->graph->as_ps(@_);
}
sub as_text {
    my $self = shift;
    return $self->graph->as_text(@_);
}

sub as_svg {
    my $self = shift;
    return $self->graph->as_svg(@_);
}

my %properties_for_operation_type;  # used by the link property check inside
sub validate {
    my $self = shift;
    
    my @errors = ();
    my @operations = $self->operations;

    my $self_id = $self->id;
    my $get_ops_for_name_tmpl = UR::BoolExpr::Template->resolve('Workflow::Operation', 'name', 'workflow_model_id')->get_normalized_template_equivalent();
    foreach my $operation (@operations) {  ## unique names
        my $rule = $get_ops_for_name_tmpl->get_rule_for_values($operation->name, $self_id);
        my @ops_with_this_name = Workflow::Operation->get( $rule );
        if (scalar @ops_with_this_name > 1) {
            push @errors, "Operation name not unique: " . $self->name . '/' . $operation->name ."\n". Data::Dumper::Dumper(\@ops_with_this_name);
        }
    }

    { ## orphans 
        my @orphans = ();
        my %possible_orphans = map { $_ => $_ } @operations;
        my $input = $self->get_input_connector;
        my $output = $self->get_output_connector;
        
        delete $possible_orphans{$input};
        delete $possible_orphans{$output};
        
        my %looked_at = ();
        
        my @opq = ($output);
        while (scalar @opq) {
            my $op = shift @opq;
            unless ($looked_at{$op}) {
                my @depended_on_by = $op->depended_on_by;

                for (@depended_on_by) {
                    delete $possible_orphans{$_};
                }
                push @opq, @depended_on_by;
            }
            $looked_at{$op} = 1;
        }
        foreach my $operation (values %possible_orphans) {
            push @errors, "Operation or its branch disconnected: " . $self->name . '/' . $operation->name;
        }
    }

    { ## circular links
        #this is so terrible, but its easy
        
        eval {
            $self->is_valid(1);
            my @ops = $self->operations_in_series;
            $self->is_valid(0);
            
        };
        if ($@ =~ /^circular links near: '(.+?)'/s) {
            push @errors, 'Operation involved in circular link: ' . $self->name . "/$1";
        } elsif ($@) {
            die $@;
        }
    }
    
    { ## connections to output
        my $output = $self->get_output_connector;
        my @depended_on_by = $output->depended_on_by;
        
        if (@depended_on_by == 0) {
            push @errors, 'Nothing connected to: ' . $self->name . '/' . $output->name;
        }
    }
        
    ## sub_models
    {
        my @submodels = Workflow::Model->get(
            workflow_model => $self  ## this is confusing, workflow_model is actually the parent
        );
        
        foreach my $m (@submodels) {
            my @e = $m->validate;
            push @errors, @e;
        }
    }
    
    ## dangling links
    
    foreach my $link ($self->links) {
        my $left_output_properties = $link->left_operation->operation_type->output_properties;
        my $right_input_properties = $link->right_operation->operation_type->input_properties;
        
        my $linkdesc = $link->left_operation->name . '->' . $link->left_property . ' to ' . $link->right_operation->name . '->' . $link->right_property;
        
        if (!grep { $link->left_property eq $_ } @{ $left_output_properties }) {
            push @errors, 'Left property not found on link: ' . $linkdesc;
        }

        if (!grep { $link->right_property eq $_ } @{ $right_input_properties }) {
            push @errors, 'Right property not found on link: ' . $linkdesc;
        }
    }
    
    if (@errors == 0) {
        $self->is_valid(1);
    } else {
        $self->is_valid(0);
    }
    
    return @errors;
}

sub operations_in_series {
    my $self = shift;

$DB::single=1;
    my %all_links;
    my %op_incoming_links;
    for my $link ( Workflow::Link->get(workflow_model_id => $self->id)) {
        $all_links{$link->id} = $link;
        $op_incoming_links{ $link->right_workflow_operation_id }->{ $link->right_property } = undef;
    }

    # The list of operations with no dependancies
    my @operations_to_check = Workflow::Operation->get(workflow_model_id => $self->id,  # operations in this workflow
                                                       'id not in' => [$self->id, keys %op_incoming_links]);
    my @op_order;

    while(@operations_to_check) {               # while S is non-empty do
        my $op = shift @operations_to_check;    # remove a node n from S
        push @op_order,$op;                     # insert n into L

        my $op_id = $op->id;
        # for each node m with an edge e from n to m do
        my @outgoing_links = Workflow::Link->get(left_workflow_operation_id => $op_id);
        foreach my $link ( @outgoing_links ) {
            my $dependant_op = $link->right_operation;

            delete $all_links{$link->id};       # remove edge e from the graph

            my $right_op_id = $link->right_workflow_operation_id;
            delete $op_incoming_links{ $right_op_id }->{ $link->right_property };

            # if m has no other incoming edges then
            if (! keys %{$op_incoming_links{ $right_op_id }}) {
                delete $op_incoming_links{ $right_op_id };

                push @operations_to_check, $dependant_op;   # insert m into S
            }
        }
    }

    # if graph has edges then
    if (keys %all_links) {
        # return error (graph has at least one cycle)
        my $message = join("\n",
                      map { $_->name }
                      map { $_->left_operation }
                      values %all_links);

        $_->{'__circularity_was_checked'} = 0 foreach @op_order;
        die "circular links near: '$message'";
    } else {
        # else return L (a topologically sorted order)
        $_->{'__circularity_was_checked'} = 1 foreach @op_order;
        return @op_order;
    }
}
    
# make a list of operations in the order of execution
sub XXoperations_in_series {
    my $self = shift;

    unless ($self->is_valid) {
        my @errors = $self->validate;
        unless (@errors == 0) {
            die join("\n", 'Cannot build an operations series for invalid workflow. Errors:', @errors);
        }
    }
    
    my %operation_tiers = map {
        $_->name => [0,$_]
    } $self->operations;

    my $maxdepth = keys %operation_tiers;
    my $depth = 0;
    my $move_deps_down;
    $move_deps_down = sub {
        my ($op,$tier) = @_;
        
        if ($depth > $maxdepth) {
            die 'circular links near: \'' . $op->name . '\'';
        }
        $operation_tiers{$op->name}->[0] = $tier;

        for ($op->dependent_operations) {
            my $new_tier = $tier + 1;
            $depth++; ## stupid way of detecting recursion
            $move_deps_down->($_,$new_tier);
            $depth--;
        }
    };
    
    foreach my $tier (0..$maxdepth) {
        my @ops = map {
            $operation_tiers{$_}->[1]
        } grep {
            $operation_tiers{$_}->[0] == $tier
        } keys %operation_tiers;
        
        foreach my $operation (@ops) {
            next if ($operation_tiers{$operation->name}->[0] != $tier); #it got moved
            $move_deps_down->($operation,$tier);
        }
    }
    
    my @op_order = map {
        $_->[1]
    } sort {
        $a->[0] <=> $b->[0] ||
        $a->[1]->name cmp $b->[1]->name
    } values %operation_tiers;

    return @op_order;
}

sub set_all_executor {
    my ($self, $executor) = @_;
    
    $self->executor($executor);
    
    foreach my $op ($self->operations) {
        if ($op->isa('Workflow::Model')) {
            $op->set_all_executor($executor);
        }
    }
    
    return $self->executor;
}

1;
