use strict;
use warnings;

package Workflow::Command::SomaticPipelineUcsc;

class Workflow::Command::SomaticPipelineUcsc {
    is => ['Workflow::Operation::Command'],
    workflow => sub { Workflow::Operation->create_from_xml(\*DATA); }
};

sub help_synopsis{
    my $self = shift;
    return "I'm a message from peck's checkout";
}

1;
__DATA__
<?xml version='1.0' standalone='yes'?>

<workflow name="Somatic Pipeline UCSC">

  <link fromOperation="input connector" fromProperty="normal_file" toOperation="Somatic Sniper" toProperty="normal_file" />
  <link fromOperation="input connector" fromProperty="tumor_file" toOperation="Somatic Sniper" toProperty="tumor_file" />
  <link fromOperation="input connector" fromProperty="sniper_output" toOperation="Somatic Sniper" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="adaptor_output" toOperation="Sniper Adaptor" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="annotate_output" toOperation="Annotate Transcript Variants" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="ucsc_output" toOperation="Annotate UCSC" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="tier_output" toOperation="Tier Variants" toProperty="output_file" />

  <link fromOperation="Somatic Sniper" fromProperty="output_file" toOperation="Sniper Adaptor" toProperty="somatic_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_file" toOperation="Tier Variants" toProperty="variant_file" />
  
  <link fromOperation="Sniper Adaptor" fromProperty="output_file" toOperation="Annotate Transcript Variants" toProperty="variant_file" />
  <link fromOperation="Sniper Adaptor" fromProperty="output_file" toOperation="Annotate UCSC" toProperty="input_file" />
  
  <link fromOperation="Annotate Transcript Variants" fromProperty="output_file" toOperation="Tier Variants" toProperty="transcript_annotation_file" />
  <link fromOperation="Annotate UCSC" fromProperty="output_file" toOperation="Tier Variants" toProperty="ucsc_file" />

  <link fromOperation="Tier Variants" fromProperty="output_file" toOperation="output connector" toProperty="tier_file" />

  <operation name="Somatic Sniper">
    <operationtype commandClass="Genome::Model::Tools::Somatic::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Sniper Adaptor">
    <operationtype commandClass="Genome::Model::Tools::Annotate::Adaptor::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate Transcript Variants">
    <operationtype commandClass="Genome::Model::Tools::Annotate::TranscriptVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate UCSC">
    <operationtype commandClass="Genome::Model::Tools::Somatic::UcscAnnotator" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Tier Variants">
    <operationtype commandClass="Genome::Model::Tools::Somatic::TierVariants" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operationtype typeClass="Workflow::OperationType::Model">
    <inputproperty>normal_file</inputproperty>
    <inputproperty>tumor_file</inputproperty>
    <inputproperty>sniper_output</inputproperty>
    <inputproperty>adaptor_output</inputproperty>
    <inputproperty>annotate_output</inputproperty>
    <inputproperty>ucsc_output</inputproperty>
    <inputproperty>tier_output</inputproperty>
    <outputproperty>tier_file</outputproperty>
  </operationtype>

</workflow>
