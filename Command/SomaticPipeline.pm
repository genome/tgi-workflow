use strict;
use warnings;

package Workflow::Command::SomaticPipeline;

class Workflow::Command::SomaticPipeline {
    is => ['Workflow::Operation::Command'],
    workflow => sub { Workflow::Operation->create_from_xml(\*DATA); }
};

sub help_synopsis{
    my $self = shift;
    return "TBD";
}

sub pre_execute {
    my $self = shift;

    # If data directory was provided... make sure it exists and set all of the file names
    if ($self->data_directory) {
        unless (-d $self->data_directory) {
            $self->error_message("Data directory " . $self->data_directory . " does not exist. Please create it.");
            return 0;
        }
        
        for my $param ($self->filenames_to_generate) {
            # set a default param if one has not been specified
            unless ($self->$param) {
                my $default_filename = $self->data_directory . "/$param.out";
                $self->status_message("Param $param was not provided... generated $default_filename as a default");
                $self->$param($default_filename);
            }
        }
    }

    # Set (hardcoded) defaults for tools that have defaults that do not agree with somatic pipeline
    unless ($self->novel_variations_no_headers) {
        $self->novel_variations_no_headers(1);
    }
    unless ($self->novel_variations_report_mode) {
        $self->novel_variations_report_mode("novel-only");
    }
    # Submitters to exclude from somatic pipeline as per dlarson. These guys submit cancer samples to dbsnp, or somesuch
    unless ($self->novel_variations_submitter_filter_not) {
        $self->novel_variations_submitter_filter_not("SNP500CANCER,OMIMSNP,CANCER-GENOME,CGAP-GAI,LCEISEN,ICRCG");
    }
    unless ($self->annotate_no_headers) {
        $self->annotate_no_headers(1);
    }
    unless ($self->transcript_annotation_filter) {
        $self->transcript_annotation_filter("top");
    }
    unless ($self->only_tier_1) {
        $self->only_tier_1(0);
    }

    # Verify all of the params that should have been provided or generated
    my $error_count = 0;
    for my $param ($self->filenames_to_generate) {
        unless ($self->$param) {
            $self->error_message("Parameter $param was not provided");
            $error_count++;
        }
    }

    if ($error_count) {
        # Shouldnt really hit this error... we should only be missing params if the user failed to provide them if they didnt provide data directory
        if ($self->data_directory) {
            $self->("$error_count params were not successfully set by pre-execute using data directory " . $self->data_directory);
        } else {
            $self->("$error_count params were not provided. All params must be specified by hand if no data directory is specified for auto generation");
        }
        return 0;
    }

    return 1;
}

sub filenames_to_generate {
    my $self = shift;

    return qw(ucsc_file 
            sniper_snp_output
            sniper_indel_output
            snp_filter_output
            adaptor_output_snp
            dbsnp_output
            annotate_output_snp
            ucsc_output
            ucsc_unannotated_output
            tier_output_snp
            indel_lib_filter_output
            adaptor_output_indel
            annotate_output_indel
            tier_output_indel
            );
}

1;
__DATA__
<?xml version='1.0' standalone='yes'?>

<workflow name="Somatic Pipeline">

  <link fromOperation="input connector" fromProperty="normal_model_id" toOperation="Somatic Sniper" toProperty="normal_model_id" />
  <link fromOperation="input connector" fromProperty="tumor_model_id" toOperation="Somatic Sniper" toProperty="tumor_model_id" />
  <link fromOperation="input connector" fromProperty="sniper_snp_output" toOperation="Somatic Sniper" toProperty="output_snp_file" />
  <link fromOperation="input connector" fromProperty="sniper_indel_output" toOperation="Somatic Sniper" toProperty="output_indel_file" />

  <link fromOperation="input connector" fromProperty="tumor_model_id" toOperation="Snp Filter" toProperty="tumor_model_id" />
  <link fromOperation="input connector" fromProperty="snp_filter_output" toOperation="Snp Filter" toProperty="output_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_snp_file" toOperation="Snp Filter" toProperty="sniper_snp_file" />

  <link fromOperation="input connector" fromProperty="adaptor_output_snp" toOperation="Sniper Adaptor Snp" toProperty="output_file" />
  <link fromOperation="Snp Filter" fromProperty="output_file" toOperation="Sniper Adaptor Snp" toProperty="somatic_file" />

  <link fromOperation="input connector" fromProperty="dbsnp_output" toOperation="Novel Variations" toProperty="output_file" />
  <link fromOperation="Sniper Adaptor Snp" fromProperty="output_file" toOperation="Novel Variations" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="novel_variations_no_headers" toOperation="Novel Variations" toProperty="no_headers" />
  <link fromOperation="input connector" fromProperty="novel_variations_report_mode" toOperation="Novel Variations" toProperty="report_mode" />
  <link fromOperation="input connector" fromProperty="novel_variations_submitter_filter_not" toOperation="Novel Variations" toProperty="submitter_filter_not" />
  
  <link fromOperation="Novel Variations" fromProperty="output_file" toOperation="Annotate Transcript Variants Snp" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="annotate_output_snp" toOperation="Annotate Transcript Variants Snp" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="annotate_no_headers" toOperation="Annotate Transcript Variants Snp" toProperty="no_headers" />
  <link fromOperation="input connector" fromProperty="transcript_annotation_filter" toOperation="Annotate Transcript Variants Snp" toProperty="annotation_filter" />

  <link fromOperation="Novel Variations" fromProperty="output_file" toOperation="Annotate UCSC" toProperty="input_file" />
  <link fromOperation="input connector" fromProperty="ucsc_output" toOperation="Annotate UCSC" toProperty="output_file" /> 
  <link fromOperation="input connector" fromProperty="ucsc_unannotated_output" toOperation="Annotate UCSC" toProperty="unannotated_file" /> 
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="Annotate UCSC" toProperty="skip" /> 
    
  <link fromOperation="input connector" fromProperty="tier_output_snp" toOperation="Tier Variants Snp" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="Tier Variants Snp" toProperty="only_tier_1" />
  <link fromOperation="Annotate UCSC" fromProperty="output_file" toOperation="Tier Variants Snp" toProperty="ucsc_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_snp_file" toOperation="Tier Variants Snp" toProperty="variant_file" />
  <link fromOperation="Annotate Transcript Variants Snp" fromProperty="output_file" toOperation="Tier Variants Snp" toProperty="transcript_annotation_file" />

  <link fromOperation="Tier Variants Snp" fromProperty="output_file" toOperation="output connector" toProperty="tier_file_snp" />

  <link fromOperation="input connector" fromProperty="indel_lib_filter_output" toOperation="Library Support Filter" toProperty="output_file" />
  <link fromOperation="Somatic Sniper" fromProperty="output_indel_file" toOperation="Library Support Filter" toProperty="indel_file" />

  <link fromOperation="input connector" fromProperty="adaptor_output_indel" toOperation="Sniper Adaptor Indel" toProperty="output_file" />
  <link fromOperation="Library Support Filter" fromProperty="output_file" toOperation="Sniper Adaptor Indel" toProperty="somatic_file" />

  <link fromOperation="Sniper Adaptor Indel" fromProperty="output_file" toOperation="Annotate Transcript Variants Indel" toProperty="variant_file" />
  <link fromOperation="input connector" fromProperty="annotate_output_indel" toOperation="Annotate Transcript Variants Indel" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="annotate_no_headers" toOperation="Annotate Transcript Variants Indel" toProperty="no_headers" />
  <link fromOperation="input connector" fromProperty="transcript_annotation_filter" toOperation="Annotate Transcript Variants Indel" toProperty="annotation_filter" />

  <link fromOperation="input connector" fromProperty="tier_output_indel" toOperation="Tier Variants Indel" toProperty="output_file" />
  <link fromOperation="input connector" fromProperty="only_tier_1" toOperation="Tier Variants Indel" toProperty="only_tier_1" />
  <link fromOperation="Library Support Filter" fromProperty="output_file" toOperation="Tier Variants Indel" toProperty="variant_file" />
  <link fromOperation="Annotate Transcript Variants Indel" fromProperty="output_file" toOperation="Tier Variants Indel" toProperty="transcript_annotation_file" />

  <link fromOperation="Tier Variants Indel" fromProperty="output_file" toOperation="output connector" toProperty="tier_file_indel" />

  <operation name="Somatic Sniper">
    <operationtype commandClass="Genome::Model::Tools::Somatic::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Snp Filter">
    <operationtype commandClass="Genome::Model::Tools::Somatic::SnpFilter" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Sniper Adaptor Snp">
    <operationtype commandClass="Genome::Model::Tools::Annotate::Adaptor::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Novel Variations">
      <operationtype commandClass="Genome::Model::Tools::Annotate::NovelVariations" typeClass="Workflow::OperationType::Command" />
  </operation>   
  <operation name="Annotate UCSC">
      <operationtype commandClass="Genome::Model::Tools::Somatic::UcscAnnotator" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate Transcript Variants Snp">
    <operationtype commandClass="Genome::Model::Tools::Annotate::TranscriptVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Tier Variants Snp">
    <operationtype commandClass="Genome::Model::Tools::Somatic::TierVariants" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operation name="Library Support Filter">
    <operationtype commandClass="Genome::Model::Tools::Somatic::LibrarySupportFilter" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Sniper Adaptor Indel">
    <operationtype commandClass="Genome::Model::Tools::Annotate::Adaptor::Sniper" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Annotate Transcript Variants Indel">
    <operationtype commandClass="Genome::Model::Tools::Annotate::TranscriptVariants" typeClass="Workflow::OperationType::Command" />
  </operation>
  <operation name="Tier Variants Indel">
    <operationtype commandClass="Genome::Model::Tools::Somatic::TierVariants" typeClass="Workflow::OperationType::Command" />
  </operation>

  <operationtype typeClass="Workflow::OperationType::Model">
    <inputproperty>normal_model_id</inputproperty>
    <inputproperty>tumor_model_id</inputproperty>

    <inputproperty isOptional="Y">only_tier_1</inputproperty>

    <inputproperty isOptional="Y">data_directory</inputproperty>
    <inputproperty isOptional="Y">ucsc_file</inputproperty>
    <inputproperty isOptional="Y">sniper_snp_output</inputproperty>
    <inputproperty isOptional="Y">sniper_indel_output</inputproperty>

    <inputproperty isOptional="Y">snp_filter_output</inputproperty>

    <inputproperty isOptional="Y">adaptor_output_snp</inputproperty>

    <inputproperty isOptional="Y">dbsnp_output</inputproperty>
    <inputproperty isOptional="Y">novel_variations_no_headers</inputproperty>
    <inputproperty isOptional="Y">novel_variations_report_mode</inputproperty>
    <inputproperty isOptional="Y">novel_variations_submitter_filter_not</inputproperty>

    <inputproperty isOptional="Y">annotate_output_snp</inputproperty>
    <inputproperty isOptional="Y">annotate_no_headers</inputproperty>
    <inputproperty isOptional="Y">transcript_annotation_filter</inputproperty>
    
    <inputproperty isOptional="Y">ucsc_output</inputproperty>
    <inputproperty isOptional="Y">ucsc_unannotated_output</inputproperty>

    <inputproperty isOptional="Y">tier_output_snp</inputproperty>

    <outputproperty>tier_file_snp</outputproperty>
    

    <inputproperty isOptional="Y">indel_lib_filter_output</inputproperty>
    <inputproperty isOptional="Y">adaptor_output_indel</inputproperty>
    <inputproperty isOptional="Y">annotate_output_indel</inputproperty>
    <inputproperty isOptional="Y">tier_output_indel</inputproperty>

    <outputproperty>tier_file_indel</outputproperty>
  </operationtype>

</workflow>

