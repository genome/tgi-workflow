
package Workflow::OperationType::Mail;

use strict;
use warnings;
use Template;
use MIME::Entity;

class Workflow::OperationType::Mail {
    isa => 'Workflow::OperationType',
    has => [
        default_input => { is => 'HASH' },
        executor => { is => 'Workflow::Executor', id_by => 'workflow_executor_id' },
    ]
};

sub create_from_xml_simple_structure {
    my ($class,$struct) = @_;

    my @input_properties = ();
    my %defaults = ();
    foreach my $prop (@{ $struct->{inputproperty} }) {
        if (ref($prop) eq 'HASH') {
            push @input_properties, $prop->{content};
            $defaults{$prop->{content}} = $prop->{default};
        } else {
            push @input_properties, $prop;
        }
    }

    my $self = $class->create(
        input_properties => \@input_properties
    );
    
    $self->default_input(\%defaults);

    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    die "not implemented yet";
    my $struct = $self->SUPER::as_xml_simple_structure;

    return $struct;
}

sub create {
    my $class = shift;
    my %args = @_;

    my $input = delete $args{input_properties} || [];
    my %input_uniq = map { $_ => 1 } @$input;
    
    $input_uniq{'email_address'} = 1;
    $input_uniq{'template_file'} = 1;
    $input_uniq{'subject'} = 1;
    
    $args{input_properties} = [keys %input_uniq];
    $args{output_properties} = ['result'];

    my $self = $class->SUPER::create(%args);

#    my $serial_executor = Workflow::Executor::Serial->create;
#    $self->executor($serial_executor);

    return $self;
}

sub execute {
    my $self = shift;
    my %inputs = @_;

    while (my ($k,$v) = each(%{ $self->default_input })) {
        $inputs{$k} ||= $v;
    }
    
    my $template_file = delete $inputs{'template_file'};

    my $tt = Template->new({
        ABSOLUTE => 1, RELATIVE => 1, 
    }) || die $Template::ERROR;

    my $output = '';
    
    $tt->process($template_file, \%inputs, \$output) || die $tt->error();
    
    my $ent = MIME::Entity->build(
        Subject => $inputs{subject},
        To => $inputs{email_address},
        Data => $output
    );

    $ent->send('sendmail');
    
    return {result => 1};
}

1;
