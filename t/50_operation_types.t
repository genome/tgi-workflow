#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 28;
use Switch;

my @operationtypes = qw{
    Block Command Converge Dummy
    Mail Model ModelInput ModelOutput
};

require_ok('Workflow');
0 && $Workflow::optypes;  ## get rid of warning when its used later
require_ok('Workflow::OperationType');

foreach my $operationtype (@operationtypes) {
    my $operationtype_class = 'Workflow::OperationType::' . $operationtype;
    require_ok($operationtype_class);
    
    switch ($operationtype) {
        case 'Block' {
            my $props = [ qw{foo bar baz bzz} ];
            
            my $o;
            ok($o = $operationtype_class->create(
                properties => $props
            ),'create ' . $operationtype);
            
            my $vals = { foo => 1, bar => 'a', baz => '%', 'bzz' => 0 };
            my $out;
            ok($out = $o->execute(%$vals), 'execute ' . $operationtype);
            is_deeply($out,$vals,'check output ' . $operationtype);
        }
        case 'Command' {
            require_ok('Workflow::Test::Command::Echo');
            my $o = $Workflow::optypes{'Workflow::Test::Command::Echo'};
            ok($o,'found ' . $operationtype);
            
            my $out;
            ok($out = $o->execute(
                input => 'Supercalifragilisticexpialidocious'
            ),'execute ' . $operationtype);
            
            is_deeply($out,{ 
                output => 'Supercalifragilisticexpialidocious',
                result => 1
            },'check output ' . $operationtype);
        }
        case 'Converge' {
            my $o;
            ok($o = $operationtype_class->create,'create ' . $operationtype);

            ok($o->input_properties([qw{ foo bar baz }]),'set input ' . $operationtype);
            ok($o->output_properties([qw{ bzz }]),'set output ' . $operationtype);

            my $out;
            ok($out = $o->execute(
                foo => [qw{a b c d e f}],
                bar => [qw{1 2 3 4 5 6}],
                baz => 'abcdef'
            ),'execute ' . $operationtype);

            is_deeply($out,{
                bzz => [qw{a b c d e f 1 2 3 4 5 6 abcdef}], result => 1
            },'check output ' . $operationtype);
        }
        case 'Dummy' {
            my $o;
            ok($o = $operationtype_class->create(
                input_properties => [qw{ foo bar baz }],
                output_properties => [qw{ bzz bxy }]
            ),'create ' . $operationtype);
            
            my $out;
            ok($out = $o->execute(),'execute ' . $operationtype);
            
            is_deeply($out,{},'check output ' . $operationtype);
        }
        case 'Mail' {
            my $dir = -d 't/template.d' ? 't/template.d' : 'template.d';
            my $o;
            ok($o = $operationtype_class->create(
                input_properties => [qw/fruit vegetable nut/],
            ),'create ' . $operationtype);

            my $out;
            ok($out = $o->execute(
                template_file => $dir . '/50_operation_types.txt',
                email_address => $ENV{USERNAME} . '@genome.wustl.edu',
                subject => 'workflow unit test',
                fruit => 'Apple',
                vegetable => 'Tomato',
                nut => 'Pecan' 
            ),'execute ' . $operationtype);

            is_deeply($out,{result => 1},'check output ' . $operationtype);
        }
        case 'Model' {
            if (0) {
            my $dir = -d 't/xml.d' ? 't/xml.d' : 'xml.d';
            my $w = Workflow::Model->create_from_xml($dir . '/00_basic.xml');
            
            my $o;
            ok($o = $w->operation_type,'found ' . $operationtype);
            
            my $out;
            ok($out = $o->execute(
                'model input string' => 'abracadabra',
                'sleep time' => 1
            ),'execute ' . $operationtype);

            is_deeply($out,{
                'model output string' => 'abracadabra',
                'today' => UR::Time->today,
                'result' => 1
            },'check output ' . $operationtype);
            }
        }
        case 'ModelInput' {
        }
        case 'ModelOutput' {
        }
    }
}

