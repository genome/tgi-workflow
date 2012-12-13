package Workflow::Command::Example::FindTests;

use strict;
use warnings;

use File::Find;
use Workflow ();

class Workflow::Command::Example::FindTests {
    is         => ['Workflow::Command'],
    has_input  => [ working_dir => { value => '.' } ],
    has_output => [ test_files => { is_optional => 1 } ],
    has_param  => [ lsf_queue => { value => $ENV{WF_TEST_QUEUE} } ]
};

sub execute {
    my $self = shift;

    my $working_path = $self->working_dir;
    my @tests        = ();

    File::Find::find(
        sub {
            if ( $File::Find::name =~ /\.t$/ and not -d $File::Find::name ) {
                push @tests, $File::Find::name;
            }
        },
        $working_path
    );
    chomp @tests;
    @tests = sort @tests;

    $self->test_files( [ map { [$_] } @tests ] );

    for (@tests) {
        $self->status_message($_);
    }

    return 1;
}

1;
