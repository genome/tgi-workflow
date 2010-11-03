
use strict;
use warnings;

use Cord;

package Cord::Command::Graph;

class Cord::Command::Graph {
    is  => ['Cord::Command'],
    has => [
        xml => {
            is          => 'String',
            doc         => 'XML file name to graph',
            is_optional => 1
        },
        cache_id => {
            is_optional => 1
        },
        class_name => {
            is          => 'String',
            is_optional => 1
        },
        png => {
            is  => 'String',
            doc => 'PNG output file to save to'
        }
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

    unless ( $self->class_name || $self->xml || $self->cache_id ) {
        $self->error_message("Must specify xml or class name to draw xml from");
        exit;
    }
    my $wf;

    if ($self->cache_id) {
        my $c = Cord::Cache->get($self->cache_id);

        die 'none found for cache_id: ' . $self->cache_id unless $c;

        $wf = $c->plan;

    } elsif ( !$self->class_name ) {
        unless ( -e $self->xml ) {
            $self->error_message( "Can't find xml file: " . $self->xml );
            exit;
        }

        $wf = Cord::Operation->create_from_xml( $self->xml );
    } else {
        eval 'use ' . $self->class_name;
        die $@ if $@;

        my $cn = $self->class_name;

        unless ( $cn->isa('Cord::Operation::Command') ) {
            $self->error_message(
                "$cn does not inherit from Cord::Operation::Command");
            exit;
        }

        $wf =
          Cord::Operation->get( $self->class_name->workflow_operation_id );
    }

    my @errors = $wf->validate;

    if ( scalar @errors ) {
        print "Validation failed!\n";
        foreach my $error (@errors) {
            print "$error\n";
        }
        exit;
    }

    $wf->as_png( $self->png );

}

1;
