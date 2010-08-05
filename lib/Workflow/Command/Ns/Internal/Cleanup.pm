package Workflow::Command::Ns::Internal::Cleanup;

use strict;
use warnings;

use Workflow ();
use IPC::Run qw(start);

class Workflow::Command::Ns::Internal::Cleanup {
    is => ['Workflow::Command'],
    has =>
      [ job_group => { doc => 'Job group to clean broken dependencies from' } ]
};

sub execute {
    my $self = shift;

    my @jobid = ();

    my @cmd = ( qw(bjobs -g), $self->job_group, qw(-u all -p) );

    open( my $fh, '-|', join( ' ', @cmd ) )
      or die "cant open bjobs: $!";

    my $head = <$fh> or die 'no header';

    if ($head =~ /No job found in job group/) {
        return 1;
    }

    while ( my $jobline = <$fh> ) {
        chomp $jobline;
        my $pendreason = <$fh>;

        if ( $pendreason =~ /Dependency condition invalid or never satisfied;/ )
        {
            my $jobid = ( $jobline =~ /^(\d+)/ )[0];

            push @jobid, $jobid;
        }
    }

    close $fh;

    my $ok = 1;
    foreach my $jobid (@jobid) {
        if ( system("bkill $jobid") ) {
            $self->error_message(
                sprintf( "Error running bkill %s: %d", $jobid, $? << 8 ) );

            $ok = 0;
        }
    }

    $ok;
}

1;
