#!/usr/bin/env perl

use Storable;
use Test::More;
use Data::Dumper;
use above 'Workflow';

use strict;
use warnings;

use_ok('Workflow::FlowAdapter');

sub model_resource_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_model_wf.xml');

    my $per_command_resources = {
        'request' => {
            'min_cores' => 1,
            'max_cores' => 1,
        },
        'reserve' => {
            'memory' => '16000'
        },
        'limit' => {
            'max_resident_memory' => 15625
        }
    };

    my $a_command_resources = Storable::dclone($per_command_resources);
    $a_command_resources->{request}{min_cores} = 4;
    $a_command_resources->{request}{max_cores} = 4;

    my $b_command_resources = Storable::dclone($per_command_resources);
    $b_command_resources->{request}{min_cores} = 3;
    $b_command_resources->{request}{max_cores} = 3;

    my $expected_resources = {
        "children" => {
            "A" => {
                "resources" => $a_command_resources,
                "queue" => "test_queue",
            },
            "B" => {
                "resources" => $b_command_resources,
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
    is_deeply($resources, $expected_resources, 'parse_resources model case');
}

sub nested_resource_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_nested_wf.xml');

    my $per_command_resources = {
        'request' => {
            'min_cores' => 1,
            'max_cores' => 1,
        },
        'reserve' => {
            'memory' => '16000'
        },
        'limit' => {
            'max_resident_memory' => 15625
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

    is_deeply($resources, $expected_resources, 'parse_resources nested case');
}


sub model_output_property_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_model_wf.xml');

    my $expected_xml = Storable::dclone($xml);

    Workflow::FlowAdapter::add_output_property_list_if_needed($xml);

    is_deeply($xml, $expected_xml, 'model output property test');
}

sub no_model_output_property_test {
    my $xml = Workflow::FlowAdapter::extract_xml_hashref(
        't/001_flow_simple_wf.xml');

    my $expected_xml = Storable::dclone($xml);
    $expected_xml->{operationtype}->{outputproperty} = [
        'output',
        'result',
    ];

    Workflow::FlowAdapter::add_output_property_list_if_needed($xml);

    is_deeply($xml, $expected_xml, 'no model output property test');
}
model_resource_test();
nested_resource_test();

model_output_property_test();
no_model_output_property_test();

done_testing();
