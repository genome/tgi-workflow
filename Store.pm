
package Workflow::Store;

use strict;
use warnings;

class Workflow::Store {
    is_transactional => 0,
    has => [
        instance_class_name => {
            is => 'String',
            default_value => 'Workflow::Operation::Instance'
        }
    ]
};

1;
