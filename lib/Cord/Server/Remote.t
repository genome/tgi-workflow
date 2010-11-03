#!/usr/bin/env perl

use strict;
use warnings;
use Test::More skip_all => 'recursive query doesnt work with sqlite'; #tests => 11;

use above 'Cord';

use_ok('Cord::Server::Remote');

my ( $r, $g ) = Cord::Server::Remote->launch();

isa_ok( $r, 'Cord::Server::Remote' );
BAIL_OUT('cannot continue tests without connection') unless defined $r;

my $sleep_op = Cord::Operation->create(
    name           => 'sleeper',
    operation_type =>
      Cord::OperationType::Command->get('Cord::Test::Command::Sleep')
);

my $plan_id = $r->add_plan($sleep_op);

ok( $plan_id, "added plan: $plan_id" );

# hack in startup since that method is not quite finished

my $instance_id = $r->_seval(
    q{
        my ($plan_id,$seconds) = @_;

        my $op = Cord::Operation->is_loaded($plan_id);
        my $exec = Cord::Executor::Server->get;

        $op->set_all_executor($exec);

        my $i = $op->execute(
            input => {
                seconds => $seconds
            }
        );
          
        return $i->id;
    }, $plan_id, 900
);

ok( $instance_id,                      "execute instance: $instance_id" );
ok( $r->print_STDOUT("stdout test\n"), 'called stdout test' );
ok( $r->print_STDERR("stderr test\n"), 'called stderr test' );

my @test_ids = ( 28, 41, 122 );
ok(
    do {
        map {
            $r->_seval(
                q{
                    my $id = shift; 
                    my @load = Cord::Operation::Instance->get(
                        id => $id,
                        -recurse => ['parent_instance_id','instance_id']
                    );
                },
                $_
            );
        } @test_ids;
    },
    'loaded test instance on server'
);

is_deeply(
    [ sort { $a <=> $b } $r->loaded_instances ],
    [ @test_ids, $instance_id ],
    'got loaded_instances'
);
ok( $r->quit, 'told server to quit' );
isa_ok( $r, 'UR::DeletedRef' );

ok( wait, 'server has quit' );

