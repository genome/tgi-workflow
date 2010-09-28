
use strict;
use warnings;

use Workflow;
use Carp;
#use XML::LibXML;
#use XML::LibXSLT;

package Workflow::Command::RunGraph;

eval "use XML::LibXML; use XML::LibXSLT;";
if (!$@) {

class Workflow::Command::RunGraph {
    is => ['Workflow::Command'],
    has => [
        instance_id => {
            is => 'Number',
            doc => 'The unique ID of the Instance to show'
        },
        png => {
            is => 'String',
            is_optional => 1,
            doc => 'PNG output file to save to'
        },
        svg => {
            is => 'String',
            is_optional => 1,
            doc => 'SVG output file to save to'
        },
        gv => {
            is => 'String',
            is_optional => 1,
            doc => 'GraphViz output file to save to',
        },
        xml => {
            is => 'String',
            is_optional => 1,
            doc => 'XML output file to save to',
        },
        deps => {
            is => 'Boolean',
            is_optional => 1,
            default_value => 0,
            doc => 'Show all dependancies for waiting nodes, not just node waiting on crashed nodes',
        },
        all_deps => {
            is => 'Boolean',
            is_optional => 1,
            default_value => 0,
            doc => 'Show all dependancies for all nodes',
        },
        _doc => {
                  is => 'XML::LibXML::Document',
                  is_transient => 1,
                  is_optional => 1,
                  doc => "The XML tool used to create all nodes of the output XML tree.",
        },
        _graph => {
                  is => 'XML::LibXML::Element',
                  is_transient => 1,
                  is_optional => 1,
                  doc => "The XML tool used to create all nodes of the output XML tree.",
        },

    ],
};
}

sub sub_command_sort_position { 10 }

sub help_brief {
"Generate a graph of a running workflow.";
}

sub help_synopsis {
    return <<"EOS"
    workflow run-graph --png example.png --instance-id 1234

    workflow run-graph --deps --svg example.svg --instance-id 5678
    By default, waiting nodes' dependancies are only shown if the depending
    node is crashed.  --deps shows all dependancies for waiting nodes.
EOS
}

sub help_detail {
    return <<"EOS"
Generate a graph of a running workflow.  
EOS
}

sub getDataNode {

    my $self = shift;
    my $key_name = shift;
    my $value = shift;

    my $doc = $self->_doc;
    
    my $data = $doc->createElement("data");
    $data->addChild($doc->createAttribute("key",$key_name));
    $data->addChild($doc->createTextNode($value));
 
    return $data; 
}

sub addKey {
    my $self = shift;
    my $id = shift;
    my $for = shift;
    my $name = shift;
    my $type = shift;
    
    my $doc = $self->_doc;
    my $graph = $self->_graph;

    my $key_el = $doc->createElement("key");
    $key_el->addChild($doc->createAttribute("id",$id) );
    $key_el->addChild($doc->createAttribute("for",$for) );
    $key_el->addChild($doc->createAttribute("attr.name",$name) );
    $key_el->addChild($doc->createAttribute("attr.type",$type) );

    $graph->addChild($key_el);
    return; 
}

sub addEdge {
    my $self = shift;
    my $source = shift;
    my $target = shift;
    
    my $doc = $self->_doc;
    my $graph = $self->_graph;

    my $edge = $doc->createElement("edge");
    $edge->addChild($doc->createAttribute("id",$source."_".$target) );
    $edge->addChild($doc->createAttribute("source",$source) );
    $edge->addChild($doc->createAttribute("target",$target) );

    $graph->addChild($edge); 
}

sub addNode {
    my $self = shift;
    my $id   = shift;
    my $name = shift;
    my $status = shift;
    my $type = shift;

    my $doc = $self->_doc;
    my $graph = $self->_graph;

    my $node = $doc->createElement("node");
    $node->addChild($doc->createAttribute("id",$id) );
    $node->addChild($self->getDataNode("name",$name) );
    $node->addChild($self->getDataNode("status",$status) );
    $node->addChild($self->getDataNode("node_type",$type) );
    $graph->addChild($node);

    return;
    #my $data = $doc->createElelemtn
}

sub execute {
    my $self = shift;

    my $doc = XML::LibXML->createDocument();
    $self->_doc($doc);
    my $root_node = $doc->createElement("graphml");
    $root_node->addChild($doc->createAttribute("xmlns", "http://graphml.graphdrawing.org/xmlns"));
    
    my $graph_node = $doc->createElement("graph");
    $graph_node->addChild($doc->createAttribute("edgedefault","undirected"));

    $self->_graph($graph_node);
    $root_node->addChild($graph_node);
    $doc->addChild($root_node);

    $self->addKey("name","node","name","string");
    $self->addKey("status","node","status","string");
    $self->addKey("node_type","node","node_type","string");
    
$DB::single=1;
    my $master_node = Workflow::Operation::Instance->get($self->instance_id);
    unless ($master_node) {
        $self->error_message("Not a valid workflow instance ID");
        return;
    }

    if ($self->all_deps) {
        $self->deps(1);
    }

    my %nodes_status = ( done => [], crashed => [], running => [], scheduled => [], 'new' => [] );

    my $nodes_text = '    ' . $self->_get_node_text($master_node) . "\n";
#    $nodes_text .= '{ rank=same; ' . $master_node->id . "; order_start;}\n";
    my $connections_text = '';

    my @still_to_process = ( $master_node );
    while (@still_to_process) {
        my $node = shift @still_to_process;

        next unless ($node->can('sorted_child_instances'));

        my @children = $node->sorted_child_instances();
        # Make all the child nodes rank together
        #$nodes_text .= '    { rank=same; ' . join('; ', map { $_->id } @children) . ";}\n";
        foreach my $child ( @children ) {
            $nodes_text .= $self->_get_node_text($child) . "\n";
            $connections_text .= sprintf('    "%d" -> "%d";' . "\n", $node->id, $child->id);
            $self->addEdge($node->id, $child->id);            
            push @{$nodes_status{$child->status}}, $child;
        }
        push @still_to_process, @children;
    }
        
    my $done_text = '';
    if (@{$nodes_status{'done'}} || @{$nodes_status{'crashed'}}) {
#        $done_text = "    subgraph cluster_done {\n        label=Done;\n        ";  # Don't draw a box around done anymore...
        my $first_time = 1;
        foreach my $node ( ( @{$nodes_status{'done'}}, @{$nodes_status{'crashed'}} ) ) {
            if ($first_time) {
                $nodes_text .= '    {rank=same; "order_done"; ' . $node->id . "; }\n";
                $first_time = 0;
            }
                
#            $done_text .= $node->id . "; ";
        }
#        $done_text .= "\n    }\n";
    }
        
    my $running_text = '';
    if (@{$nodes_status{'running'}} || @{$nodes_status{'scheduled'}}) {
        $running_text = "    subgraph cluster_now {\n        color=blue; label=Now;\n    ";
        my $first_time = 1;
        foreach my $node ( ( @{$nodes_status{'running'}}, @{$nodes_status{'scheduled'}} ) ) {
            if ($first_time) {
                $nodes_text .= '    {rank=same; "order_now"; ' . $node->id . "; }\n";
                $first_time = 0;
            }
            $running_text .= $node->id . "; ";
        }
        $running_text .= "\n    }\n";
    }

    my $waiting_text = '';
    if (@{$nodes_status{'new'}}) {
        $waiting_text = "    subgraph cluster_waiting {\n    label=Waiting;\n    ";
        my $first_time = 1;
        foreach my $node ( @{$nodes_status{'new'}} ) {
            if ($first_time) {
                $nodes_text .= '    {rank=same; "order_waiting"; ' . $node->id . "; }\n";
                $first_time = 0;
            }
            $waiting_text .= $node->id . "; ";
        }
        $waiting_text .= "\n    }\n";
    }

    my $dependancies_text = '';
    foreach my $status ( qw(done crashed running scheduled new) ) {
        next unless ($status eq 'new' || $self->all_deps);

        foreach my $node ( @{$nodes_status{$status}} ) {
            my @depended = $node->depended_on_by;
            foreach my $d ( @depended ) {
                my $color;
                if ($d->status eq 'crashed') {
                    $color = 'red';
                } elsif ($d->status eq 'done') {
                    next unless ($self->deps);
                    $color = 'green';
                } elsif ($d->status eq 'running') {
                    next unless ($self->deps);
                    $color = 'blue';
                } elsif ($d->status eq 'new') {
                    next unless ($self->deps);
                    $color = 'lightgray';
                } else {
                    next unless ($self->deps);
                    $color = 'black';
                }
                $dependancies_text .= sprintf("%d -> %d [style=dashed,constraint=false,color=$color];\n",
                                              $node->id, $d->id);
            }
        }
    }

    my $graph_label = $master_node->name;
    my $output = <<"GRAPH";
digraph workflow {
    label="$graph_label";
    rankdir=LR;
    "order_start" -> "order_done";
    "order_done" -> "order_now" [minlen=3];
    "order_now" -> "order_waiting" [minlen=3];
    order_start [rank=min];
    order_waiting [rank=max];

  // Running subgraph
$running_text

  // Waiting subgraph
$waiting_text

  // All the nodes
$nodes_text

  // All the connections
$connections_text

  // All the dependancies
$dependancies_text
}
GRAPH

    if (my $outfile = $self->png) {
        my $cmdline;
        if ($outfile eq '-') {
            $cmdline = 'dot -Tpng';
        } else {
            $cmdline = "dot -Tpng -o $outfile";
        }
        open(my $gv, "| $cmdline") || Carp::croak("Can't start dot (graphviz): $!");
        $gv->print($output,"\n");
        $gv->close();
        if ($?) {
            $self->error_message("dot exited abnormally");
        }
    }
    if (my $outfile = $self->svg) {
        my $cmdline;
        if ($outfile eq '-') {
            $cmdline = 'dot -Tsvg';
        } else {
            $cmdline = "dot -Tsvg -o $outfile";
        }
        open(my $gv, "| $cmdline") || Carp::croak("Can't start dot (graphviz): $!");
        $gv->print($output,"\n");
        $gv->close();
    }
    if (my $outfile = $self->gv) {
        open (my $f, ">$outfile");
        $f->print($output,"\n");
        $f->close();
    }
    if (my $outfile = $self->xml) {
        open (my $f, ">$outfile");
        $f->print($doc->toString(1),"\n");
        $f->close();
    } 
}

        
sub execute_old {
    my $self = shift;
    
$DB::single=1;
    my $i = Workflow::Operation::Instance->get($self->instance_id);
    unless ($i) {
        $self->error_message("Not a valid workflow instance ID");
        return;
    }
    
    my $running = [];
    my $done = [];
    my $new = [];
    
    my $edges_text = $self->_get_graph_edges($i,$done,$running,$new,$i);

    my $nodes_text = "{ rank=min; " . $self->_get_node_text($i) . " }\n";
  
    my $done_text = '';
    if (@$done) {
        $nodes_text .= "{ rank=source;\n";
        $done_text = "subgraph cluster_done {\n  label=Done;\n";
        foreach my $node ( @$done ) {
            $done_text .= $node->id . "; ";
            $nodes_text .= "  " . $self->_get_node_text($node) . "\n";
        }
        $done_text .= "\n}\n";
        $nodes_text .= "\n}\n";
    }
    my $running_text = '';
    if (@$running) {
        $running_text = "subgraph cluster_now {\ncolor=lightblue;label=Now;\n";
        foreach my $node ( @$running ) {
            $running_text .= $node->id . "; ";
            $nodes_text .= $self->_get_node_text($node) . "\n"; 
        }
        $running_text .= "\n}\n";
    }
    my $new_text = '';
    if (@$new) {
        $nodes_text .= "{ rank=sink;\n";
        $new_text = "subgraph cluster_waiting {\nlabel=Waiting;rank=sink;\n";
        foreach my $node ( @$new ) {
            $new_text .= $node->id . "; ";
            $nodes_text .= "  ".$self->_get_node_text($node) . "\n";
        }
        $new_text .= "\n}\n";
        $nodes_text .= "\n}\n";
    }

    my $output = "digraph workflow {\nlabel=\"".$i->name."\";\nrankdir=LR;\n";
    $output .= $done_text . $running_text . $new_text;
    $output .= $nodes_text . $edges_text . "}\n";
#    $output .= "{ rank=source; cluster_done; }\n{ rank=sink; cluster_waiting; }\n";
    

    if (my $outfile = $self->png) {
        open(my $gv, "| dot -Tpng -o $outfile") || Carp::croak("Can't start dot (graphviz): $!");
        $gv->print($output,"\n");
        $gv->close();
    }
    if (my $outfile = $self->gv) {
        open (my $f, ">$outfile");
        $f->print($output,"\n");
        $f->close();
    }
   
    

}

sub _get_node_text {
    my($self,$node) = @_;

    my $status_attribs;
    if ( $node->status eq 'done' ) {
        $status_attribs = ',style=filled,color=green';
    } elsif ($node->status eq 'running') {
        $status_attribs = ',style=filled,color=lightblue';
    } elsif ($node->status eq 'scheduled') {
        $status_attribs = ',style=filled,color=lightgrey';
    } elsif ($node->status eq 'new') {
        $status_attribs = '';
    } elsif ($node->status eq 'crashed') {
        $status_attribs = ',style=filled,color=red';
    } else {
        print STDERR "Node has unknown status: ".Data::Dumper::Dumper($node),"\n";
    }

    my $node_type = "operation";
    if ($node->isa('Workflow::Model::Instance')) {
        $status_attribs .= ",shape=doublecircle";
        $node_type = "instance";
    }

    #my $text = sprintf('"%d" [label="%s",URL="http://www.google.com/"%s];',
    my $text = sprintf('"%d" [label="%s"%s];',
                       $node->id, 
                       $node->name,
                       $status_attribs);

    $self->addNode($node->id,$node->name,$node->status,$node_type);
    
    return $text;
}

sub _get_graph_edges {
    my($self,$node,$done,$running,$new,$workflow_master) = @_;

    if ($node ne $workflow_master) {
        my $status = $node->status;
        if ($status eq 'done' || $status eq 'crashed') {
            push @$done, $node;
        } elsif ($status eq 'running' || $status eq 'scheduled') {
            push @$running, $node;
        } elsif ($status eq 'new') {
            push @$new, $node;
        }
    }
 
    my $text = '';
    if ($node->can('sorted_child_instances')) {
        foreach my $child ( $node->sorted_child_instances ) {
            $text .= sprintf('"%d" -> "%d";' . "\n", $node->id, $child->id);
        

            $text .= $self->_get_graph_edges($child, $done, $running, $new, $workflow_master);
        }
    }
    return $text;
}


1;
