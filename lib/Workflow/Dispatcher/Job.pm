package Workflow::Dispatcher::Job;

class Workflow::Dispatcher::Job {
    has => [
        resource => { is => 'Workflow::Resource' },
        command => { is => 'Text' }
    ]
}
