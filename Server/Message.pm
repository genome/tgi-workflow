
package Workflow::Server::Message;

use strict;
use warnings;

class Workflow::Server::Message {
    is_transactional => 0,
    has => [
        type => { is => 'Text' },
        heap => { is => 'HASH' }
    ]
};

1;
