package Workflow::FlowAdapter::Error;

use strict;
use warnings;

use Workflow;

class Workflow::FlowAdapter::Error {
    has => [
        error => {
            is => 'Text',
        },
    ]
};

1;
