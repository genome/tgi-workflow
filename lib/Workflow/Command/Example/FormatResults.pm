package Workflow::Command::Example::FormatResults;

use strict;
use warnings;

use Workflow ();
use Data::Dumper qw/Dumper/;

class Workflow::Command::Example::FormatResults {
    is        => ['Workflow::Command'],
    has_input => [
        test_files   => { is => 'ARRAY' },
        test_results => { is => 'ARRAY' }
    ],
    has_output => [ failed_tests => { is_optional => 1 } ],
    has_param  => [ lsf_queue    => { value       => $ENV{WF_TEST_QUEUE} } ]
};

sub execute {
    my $self = shift;

    my $f = $self->test_files;
    my $r = $self->test_results;

    if ( scalar @$f != scalar @$r ) {
        die "test count and result count differ:\n" . Dumper($f,$r);
    }

    my $failed = [];
    for ( my $i = 0 ; $i < scalar @$f ; $i++ ) {
        if ( !$r->[$i] ) {
            my $str = join( ' ', @{ $f->[$i] } );
            push @$failed, $str;
        }
    }

    $self->failed_tests($failed);

    return scalar @$failed ? 0 : 1;
}

1;
