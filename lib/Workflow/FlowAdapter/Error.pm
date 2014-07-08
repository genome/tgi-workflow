package Workflow::FlowAdapter::Error;

use strict;
use warnings;

use Workflow;

class Workflow::FlowAdapter::Error {
    has => [
        error => {
            is => 'Text',
        },
        name => { is => 'Text', is_constant => 1, default_value => __PACKAGE__ },
    ]
};

1;
