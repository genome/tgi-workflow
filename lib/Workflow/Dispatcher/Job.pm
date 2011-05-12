package Workflow::Dispatcher::Job;

class Workflow::Dispatcher::Job {
    has => [
        resource => { is => 'Workflow::Resource' },
        command => { is => 'Text' },
        queue => { is => 'Text', is_optional => 1 },
        stdout => { is => 'Text', is_optional => 1 },
        stderr => { is => 'Text', is_optional => 1 }
    ]
}
