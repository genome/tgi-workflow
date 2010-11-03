package Cord::Test::Command::SequenceLength;

use strict;
use warnings;

# dummy the return output so we dont have to depend on bioperl
#use Bio::Seq;
#use Bio::SeqIO;
use Cord;

class Cord::Test::Command::SequenceLength {
    is => ['Cord::Test::Command'],
    has => [
        fasta_file => { 
            is => 'String', 
            is_input => 1,
            doc => 'fasta file name' 
        },
        sequence_length => { 
            is => 'Integer', 
            is_output => 1,
            is_optional => 1, 
            doc => 'Sequence Length' 
        }
    ],
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

    #my $seqio = Bio::SeqIO->new(-file => $file, -format => 'Fasta');
    #my $seq        = $seqio->next_seq();

    $self->sequence_length(1024*3); #$seq->length());

    return 1;
}
 
1;
