package Cord::Command::Example::FormatResults;

use strict;
use warnings;

use Cord ();
use Data::Dumper qw/Dumper/;

class Cord::Command::Example::FormatResults {
    is        => ['Cord::Command'],
    has_input => [
        test_files   => { is => 'ARRAY' },
        test_results => { is => 'ARRAY' }
    ],
    has_output => [ failed_tests => { is_optional => 1 } ],
    has_param  => [ lsf_queue    => { value       => 'short' } ]
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
