
package Workflow::Store::Db;

use strict;

class Workflow::Store::Db {
    isa => 'Workflow::Store',
    is_transactional => 0
};

sub sync {
    my ($self, $operation_instance) = (@_);

    my $saved_instance = $operation_instance->save_instance;
    UR::Context->commit;

    return $saved_instance;
}

1;
