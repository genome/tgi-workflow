package Cord::Command::Example::Test;

use strict;
use warnings;
use Data::Dumper qw/Dumper/;

class Cord::Command::Example::Test {
    is       => ['Cord::Operation::Command'],
    workflow => sub {
        my $file = __FILE__;
        $file =~ s/\.pm$/.xml/;
        Cord::Operation->create_from_xml($file);
    }
};

sub pre_execute {
    my $self = shift;

    my $urrunner = $self->_operation->operations( name => 'runner' );

    $urrunner->operation_type->lsf_queue('short');
    $urrunner->operation_type->lsf_resource("-R 'select[type==LINUX64 && model!=Opteron250 && tmp>1000 && mem>4000] rusage[tmp=1000, mem=4000]'");
}

sub post_execute {
    my $self = shift;

    my %hash = map { $_ => $self->$_ } $self->output_property_names;

    print Dumper( \%hash );

    my $failstring = join(' ', @{ $self->failures });

    system('ur test run --lsf ' . $failstring);

    return $self->result;
}

1;
