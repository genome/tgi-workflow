use strict;

use above 'Workflow';
use Test::More tests => 4;

use_ok('Workflow::Test::Widget');

my @widgets = map {
    Workflow::Test::Widget->new($_)
} ({
    size => 'large', color => 'red', shape => 'boxy'
}, {
    size => 'medium', color => 'blue', shape => 'round'
}, {
    size => 'small', color => 'green', shape => 'triangular'
});

ok(@widgets == 3, 'made 3 widgets');

my $cmd = Workflow::Test::Command::WidgetManyReader->create(
    widget => \@widgets
);

ok($cmd, 'created command object');

my $rv = $cmd->execute();
ok($rv > 0, 'command returned true');
