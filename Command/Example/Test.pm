package Workflow::Command::Example::Test;

use strict;
use warnings;
use Data::Dumper qw/Dumper/;

class Workflow::Command::Example::Test {
    is       => ['Workflow::Operation::Command'],
    workflow => sub {
        my $file = __FILE__;
        $file =~ s/\.pm$/.xml/;
        Workflow::Operation->create_from_xml($file);
    }
};

sub pre_execute {
    my $self = shift;

    my $urrunner = $self->_operation->operations( name => 'runner' );

    $urrunner->operation_type->lsf_queue('short');
    $urrunner->operation_type->lsf_resource('-R select[type=LINUX64] -W 10');
}

sub post_execute {
    my $self = shift;

    my %hash = map { $_ => $self->$_ } $self->output_property_names;

    print Dumper( \%hash );

    return $self->result;
}

1;
