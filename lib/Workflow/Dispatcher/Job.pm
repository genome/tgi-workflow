package Workflow::Dispatcher::Job;

class Workflow::Dispatcher::Job {
    has => [
        resource => { is => 'Workflow::Resource' },
        command => { is => 'Text' },
        # group is e.g. /workflow-worker2 in workflow
        group => { is => 'Text', is_optional => 1 },
        name => { is => 'Text', is_optional => 1 },
        project => { is => 'Text', is_optional => 1 },
        queue => { is => 'Text', is_optional => 1 },
        stdout => { is => 'Text', is_optional => 1 },
        stderr => { is => 'Text', is_optional => 1 }
    ]
}
