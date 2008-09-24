
package Workflow::Store::Db;

use strict;

class Workflow::Store::Db {
    isa => 'Workflow::Store',
    is_transactional => 0,
    has => [
        instance_class_name => {
            is => 'String',
            default_value => 'Workflow::Store::Db::Operation::Instance'
        }
    ]
};

sub sync {
    my ($self, $operation_instance) = (@_);

    UR::Context->commit;
    return $operation_instance;
}

1;
