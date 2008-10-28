
package Workflow::Store::Db;

use strict;

# weird things happen if I don't use these in the correct order
use Workflow::Store::Db::Operation::Instance;
use Workflow::Store::Db::Model::Instance;

class Workflow::Store::Db {
    isa => 'Workflow::Store',
    is_transactional => 0,
    has => [
        class_prefix => {
            value => 'Workflow::Store::Db'
        }
    ]
};

sub sync {
    my ($self, $operation_instance) = (@_);

#    UR::Context->commit;
    return $operation_instance;
}

1;
