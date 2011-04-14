package Workflow::LsfParser;

use strict;
use warnings;

class Workflow::LsfParser {
    has => [
        resource => { is => 'Workflow::Resource' },
        queue => { is => 'String' },
    ],
};
