
package Cord::Test::Widget;

use base qw(Class::Accessor);
use strict;

Cord::Test::Widget->mk_accessors(qw(size color shape));

1;
