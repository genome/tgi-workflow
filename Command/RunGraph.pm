
use strict;
use warnings;

use Workflow;
use Carp;

package Workflow::Command::RunGraph;

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
        gv => {
            is => 'String',
            is_optional => 1,
            doc => 'GraphViz output file to save to',
        },
    ]
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Show";
}

sub help_synopsis {
    return <<"EOS"
    workflow graph --xml example.xml --png output.png 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for diagnostic purposes.
EOS
}

sub execute {
    my $self = shift;
    
$DB::single=1;
    my $i = Workflow::Store::Db::Operation::Instance->get($self->instance_id);
    unless ($i) {
        $self->error_message("Not a valid workflow instance ID");
        return;
    }
    
    my $running = [];
    my $done = [];
    my $new = [];
    
    my $edges_text = $self->_get_graph_edges($i,$done,$running,$new,$i);

    # rankdir=LR
    my $nodes_text = "{ rank=min; " . $self->_get_node_text($i) . " }\n";

    my $done_text = '';
    if (@$done) {
        $nodes_text .= "{ rank=source;\n";
        $done_text = "subgraph cluster_done {\n  label=Done;\n";
        foreach my $node ( @$done ) {
            $done_text .= $node->id . "; ";
            $nodes_text .= "  " . $self->_get_node_text($node);
        }
        $done_text .= "\n}\n";
        $nodes_text .= "\n}\n";
    }
    my $running_text = '';
    if (@$running) {
        $running_text = "subgraph cluster_now {\ncolor=lightblue;label=Now;\n";
        foreach my $node ( @$running ) {
            $running_text .= $node->id . "; ";
            $nodes_text .= $self->_get_node_text($node);
        }
        $running_text .= "\n}\n";
    }
    my $new_text = '';
    if (@$new) {
        $nodes_text .= "{ rank=sink;\n";
        $new_text = "subgraph cluster_waiting {\nlabel=Waiting;rank=sink;\n";
        foreach my $node ( @$new ) {
            $new_text .= $node->id . "; ";
            $nodes_text .= "  ".$self->_get_node_text($node);
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
        open (my $f, ">/tmp/gv.graph");
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
        $status_attribs = ',color=blue';
    } elsif ($node->status eq 'scheduled') {
        $status_attribs = ',style=filled,color=lightgrey';
    } elsif ($node->status eq 'new') {
        $status_attribs = '';
    } elsif ($node->status eq 'crashed') {
        $status_attribs = ',style=filled,color=red';
    } else {
        print STDERR "Node has unknown status: ".Data::Dumper::Dumper($node),"\n";
    }

    if ($node->isa('Workflow::Store::Db::Model::Instance')) {
        $status_attribs .= ",shape=doublecircle";
    }

    my $text = sprintf('"%d" [label="%s"%s];'."\n", $node->id, 
                                                   $node->name,
                                                   $status_attribs);
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
