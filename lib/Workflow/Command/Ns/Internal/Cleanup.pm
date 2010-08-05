package Workflow::Command::Ns::Internal::Cleanup;

use strict;
use warnings;

use Workflow ();
use IPC::Open3 qw(open3);
use IO::Select;

class Workflow::Command::Ns::Internal::Cleanup {
    is => ['Workflow::Command'],
    has =>
      [ job_group => { doc => 'Job group to clean broken dependencies from' } ]
};

sub execute {
    my $self = shift;

    my @jobid = ();
    my @cmd = ( qw(bjobs -g), $self->job_group, qw(-u all -p) );

    my $s = IO::Select->new();

    my $wtr = \*WTR;
    my $err = \*ERR;

    my $pid = open3( '<&STDIN', $wtr, $err, join( ' ', @cmd ) );

    $s->add( $wtr, $err );

    my $ebuf = '';
    my $obuf = '';

  O: while ( my @ready = $s->can_read() ) {
        foreach my $fh (@ready) {
            if ( $fh == $err ) {
                my $len = sysread $err, $ebuf, 4096, length($ebuf);

                if ( $len == 0 ) {
                    warn 'eof e';
                    $s->remove($err);
                } elsif ( $len == -1 ) {
                    die "read err: $!";
                } elsif ( $len < 4096 ) {
                    my $line = substr( $ebuf, 0, index( $ebuf, "\n" ) + 1, '' );

                    if ( $line =~ /No job found in job group/ ) {
                        return 1;
                    }
                }

            } elsif ( $fh == $wtr ) {
                my $len = sysread $wtr, $obuf, 4096, length($obuf);

                if ( $len == 0 ) {
                    warn 'eof o';
                    $s->remove($wtr);
                } elsif ( $len == -1 ) {
                    die "read out: $!";
                } elsif ( $len < 4096 ) {
                    if ( my $a = index( $obuf, "\n" ) ) {
                        if ( my $b = index( $obuf, "\n", $a + 1 ) ) {
                            my $pendline = substr( $obuf,     0, $b + 1, '' );
                            my $jobline  = substr( $pendline, 0, $a + 1, '' );

                            if ( $pendline =~
/Dependency condition invalid or never satisfied;/
                              )
                            {
                                my $jobid = ( $jobline =~ /^(\d+)/ )[0];
                                push @jobid, $jobid;
                            }
                        }
                    }
                }
            }
        }
    }

    close $wtr;
    close $err;

    waitpid $pid, 0;

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
