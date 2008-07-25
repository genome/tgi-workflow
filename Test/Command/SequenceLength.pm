package Workflow::Test::Command::SequenceLength;

use strict;
use warnings;

use Bio::Seq;
use Bio::SeqIO;
use Workflow;

class Workflow::Test::Command::SequenceLength {
    is => ['Workflow::Test::Command'],
    has => [
        fasta_file => { is => 'String', doc => 'fasta file name' },
        sequence_length => { is => 'Integer', is_optional => 1, doc => 'Sequence Length' }
    ],
};

operation_io Workflow::Test::Command::SequenceLength {
    input  => [ 'fasta_file' ],
    output => [ 'sequence_length' ],
};

sub sub_command_sort_position { 10 }

sub help_brief {
}

sub help_synopsis {
    return <<"EOS"
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;
    
    my $file = $self->fasta_file;

    my $seqio = Bio::SeqIO->new(-file => $file, -format => 'Fasta');
    my $seq        = $seqio->next_seq();

    $self->sequence_length($seq->length());

    return 1;
}
 
1;
