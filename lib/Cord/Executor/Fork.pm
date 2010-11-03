
## This module may be broken

=pod
package Cord::Executor::Fork;

use strict;
use forks qw(debug);
use forks::shared;

threads->debug(1);

class Cord::Executor::Fork {
    isa => 'Cord::Executor',
    has => [
        threads => { }
    ]
};

our %opdone;

sub execute {
    my $self = shift;
    my %params = @_;

    if (!$self->threads) {
        $self->threads([]);
    }

    my $op = $params{operation};
    my $opdata = $params{operation_instance};

    $opdone{$opdata->id} = 0;
    share($opdone{$opdata->id});

    my $thread = threads->create(sub {
        $self->status_message('exec/' . $opdata->dataset->id . '/' . $op->name);
        my $outputs = $op->operation_type->execute(%{ $opdata->input }, %{ $params{edited_input} });
        {
            lock($opdone{$opdata->id});
            $opdone{$opdata->id} = 1;
        }
        return $outputs;
    });

    $self->threads([@{ $self->threads }, [$thread,$opdata]]);

    return;
}

sub wait {
    my $self = shift;

    while (1) {
        my @bucket = ();
        while (my $v = shift @{ $self->threads }) {
            my ($thread,$opdata) = @{ $v };
            unless ($opdone{$opdata->id}) {
                push @bucket, $v;
                next;
            }
            delete $opdone{$opdata->id};

            my $outputs = $thread->join;

            $opdata->output({ %{ $opdata->output }, %{ $outputs } });
            $opdata->is_done(1);

            $opdata->completion;
        }
        $self->threads(\@bucket);
        last if (@{ $self->threads } == 0);
        sleep 1 if (join('', values %opdone) == 0);
    }
    
    $self->threads([]);
}
=cut


1;
