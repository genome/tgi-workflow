
package Workflow::Model;

use strict;
use warnings;
use GraphViz;
use XML::Simple;

use above 'Workflow';

class Workflow::Model {
    isa => 'Workflow::Operation',
    is_transactional => 0,
    has => [
        operations => { is => 'Workflow::Operation', is_many => 1 },
        links => { is => 'Workflow::Link', is_many => 1 },
    ]
};

sub create {
    my $class = shift;
    my %params = @_;

    my $optype = $params{operation_type};
    unless ($params{operation_type}) {
        $optype = Workflow::OperationType::Model->create(
            input_properties => delete($params{input_properties}) || [],
            output_properties => delete($params{output_properties}) || []
        );

        $params{operation_type} = $optype;
    }

    my $self = $class->SUPER::create(%params);

    $self->add_operation(
        name => 'input connector',
        operation_type => Workflow::OperationType::ModelInput->create(
            input_properties => [],
            output_properties => $optype->input_properties
        ),
    );
    $self->add_operation(
        name => 'output connector',
        operation_type => Workflow::OperationType::ModelOutput->create(
            input_properties => $optype->output_properties,
            output_properties => [],
        ),
    );

    return $self;
}

sub create_from_xml {
    my ($class, $filename) = @_;

    my $struct = XMLin($filename, KeyAttr=>[], ForceArray=>[qw/operation property inputproperty outputproperty link/]);
    my $self = $class->create_from_xml_simple_structure($struct);

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

    my $operations = delete $struct->{operation};
    my $links = delete $struct->{link};

    my $self = $class->SUPER::create_from_xml_simple_structure($struct,%params);

    foreach my $op_struct (@$operations) {
        my $op = Workflow::Operation->create_from_xml_simple_structure($op_struct,workflow_model=>$self);
    }

    foreach my $link_struct (@$links) {
        my $link = Workflow::Link->create_from_xml_simple_structure($link_struct,workflow_model=>$self);
    }

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = $self->SUPER::as_xml_simple_structure;

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

sub execute {
    my $self = shift;
    my %inputs = (@_);

    # connect all links on the operation objects
    
    my @all_links = $self->links;
    foreach my $link (@all_links) {
        $link->set_inputs;
    }

    my $input_connector = $self->get_input_connector;

    $input_connector->outputs({%inputs, result=>1});
    
    my @all_incomplete_operations = $self->operations;
    my $loop_limit = 10_000;
    while (scalar @all_incomplete_operations && $loop_limit) {
        INNER: for my $i (0 .. $#all_incomplete_operations) {
            my $op = $all_incomplete_operations[$i];
            if ($op->is_ready && !$op->is_done) {
                $self->status_message($op->name . " is ready, running it");
                if ($op->Workflow::Operation::execute) {
                    splice(@all_incomplete_operations,$i,1);
                    last INNER;
                }
            }
        }
#        $self->status_message("still has incomplete operations");
        $loop_limit--;
    }
    if (@all_incomplete_operations) {
        $self->error_message("looped a lot and not finished");
        return;
    }

    my $output_connector = $self->get_output_connector;

    my $final_outputs = $output_connector->inputs();
    foreach my $output_name (%$final_outputs) {
        if (UNIVERSAL::isa($final_outputs->{$output_name},'Workflow::Link')) {
            $final_outputs->{$output_name} = $final_outputs->{$output_name}->left_value;
        }
    }

    return $final_outputs;
}

1;
