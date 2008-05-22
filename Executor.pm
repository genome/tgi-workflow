
package Workflow::Executor;

use strict;

class Workflow::Executor {
    has => [
        ended_callback => { is => 'CODE' },
        exec_queue => { is => 'ARRAY' },
    ]
};

1;
