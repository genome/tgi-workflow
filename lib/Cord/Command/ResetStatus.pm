package Cord::Command::ResetStatus;

use strict;
use warnings;

use Cord;

class Cord::Command::ResetStatus {
    is => 'Cord::Command',
    has => [
        instance_ids => {
            is => 'Text',
            doc => 'A comma delimited list of instance ids',
        },
    ],
    has_optional => [
        status => {
            is => 'Text',
            doc => 'Status that instances should be set to',
            default => 'crashed',
            valid_values => ['crashed', 'new', 'scheduled', 'done'],
        },
    ],
};

sub help_brief { return 'Reset status on a list of ids' };
sub help_synopsis { return help_brief() };
sub help_detail {
    return 'Given a comma delimited list of instance id, resets their status to whatever is provided'
}

sub execute {
    my $self = shift;

    my @instance_ids = split(',', $self->instance_ids);
    unless (@instance_ids) {
        $self->warning_message('Not given any instance ids!');
        return 0;
    }

    my @instances = Cord::Operation::Instance->get(\@instance_ids);
    unless (@instances) {
        $self->warning_message("Could not find any instances with supplied IDs " . $self->instance_ids);
        return 0;
    }

    unless (@instances == @instance_ids) {
        my %ids;
        map { $ids{$_->id} = 1 } @instances;
        for my $instance_id (@instance_ids) {
            next if exists $ids{$instance_id};
            $self->warning_message("Did not find instance with ID $instance_id");
        }
    }

    for my $instance (@instances) {
        $instance->status($self->status);
    }

    return 1;
}
1;

