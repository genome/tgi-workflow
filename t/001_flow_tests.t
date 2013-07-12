#!/usr/bin/env perl

use Test::More;
use Data::Dumper;
use above 'Workflow';

use strict;
use warnings;

use_ok('Workflow::FlowAdapter');

sub simple_resource_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_simple_wf.xml');

    my $per_command_resources = {
        'require' => {
            'min_proc' => 1
        },
        'reserve' => {
            'memory' => '16000'
        },
        'limit' => {
            'max_resident_memory' => 16000000
        }
    };

    my $expected_resources = {
        "children" => {
            "A" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
            "B" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
            "C" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
            "D" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
        },
    };


    my $resources = Workflow::FlowAdapter::parse_resources($xml);
    is_deeply($expected_resources, $resources, 'parse_resources simple case');
}

sub nested_resource_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_nested_wf.xml');

    my $per_command_resources = {
        'require' => {
            'min_proc' => 1
        },
        'reserve' => {
            'memory' => '16000'
        },
        'limit' => {
            'max_resident_memory' => 16000000
        }
    };

    my $per_model_resources =  {
        "children" => {
            "A" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
            "B" => {
                "resources" => $per_command_resources,
                "queue" => "test_queue",
            },
        },
    };

    my $expected_resources = {
        "children" => {
            "Inner Model A" => $per_model_resources,
            "Inner Model B" => $per_model_resources,
        },
    };


    my $resources = Workflow::FlowAdapter::parse_resources($xml);

    is_deeply($expected_resources, $resources, 'parse_resources nested case');
}

simple_resource_test();
nested_resource_test();

done_testing();
