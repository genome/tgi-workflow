package Workflow::Job::Event::Lsf;

use strict;
use Workflow;

class Workflow::Job::Event::Lsf {
    is              => 'Workflow::Job::Event',
    attributes_have => [
        populate_from => {
            is          => 'String',
            is_optional => 1
        }
    ],
    has => [
        __populated => {
            is    => 'Boolean',
            value => 0
        },
        specified_hosts => { populate_from => 'Specified Hosts' },
        error_file => { populate_from => 'Error File' },
        cwd => { populate_from => 'CWD' },
        submitted_from_host => { populate_from => 'Submitted from host' },
        output_file => { populate_from => 'Output File' },
        requested_resources => { populate_from => 'Requested Resources' },
        execution_cwd => { populate_from => 'Execution CWD' },
        execution_home => { populate_from => 'Execution Home' },
        started_on => { populate_from => 'Started on' }
    ]
};

sub __populate {
    my $self  = shift;
    my $ehash = shift;

    return if $self->__populated;

    my @property_meta = $self->__meta__->all_property_metas();
    my %map = map { $_->property_name => $_->{'populate_from'} } @property_meta;
    
    while (my ($prop,$key) = each %map) {
        next unless $key;
        $self->$prop( delete $ehash->{$key});
    }

    $self->{__bare} = $ehash;

    $self->__populated(1);
}


1;
