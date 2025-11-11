/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_seq_data_validation_pipeline'

include { BAM_FILE_INTEGRITY  } from '../subworkflows/local/bam_file_integrity/main'
include { VCF_FILE_INTEGRITY  } from '../subworkflows/local/vcf_file_integrity/main'
include { FASTQ_FILE_INTEGRITY  } from '../subworkflows/local/fastq_file_integrity/main'
include { FILE_INTEGRITY_REPORT  } from '../subworkflows/local/generate_report/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow SEQ_DATA_VALIDATION {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = channel.empty()
    ch_integrity_reports = channel.empty()
    ch_multiqc_files = channel.empty()

    // inputs
    ch_fasta = params.fasta ? channel.value(file(params.fasta, checkIfExists:true)) : channel.value([])
    ch_fai   = params.fai ? channel.value(file(params.fai, checkIfExists:true)) : channel.value([])
    ch_dict   = params.fasta_dict ? channel.value(file(params.fasta_dict, checkIfExists:true)) : channel.value([])
    ch_dbsnp = params.dbsnp ? channel.value(file(params.dbsnp, checkIfExists:true)) : channel.value([])
    ch_intervals = params.regions_bed ? channel.value(file(params.regions_bed, checkIfExists: true)) : channel.value([])


    // Branch input based on file type
    ch_samplesheet_parsed = ch_samplesheet
        .branch { meta, files ->
        fastq: meta.fileType == "FASTQ"
        aln: meta.fileType in ["BAM", "CRAM"]
            [ meta - meta.subMap('lane','runId'), files[0], files[1] ]
        vcf:   meta.fileType in ["VCF","GVCF"]
            [ meta - meta.subMap('lane','runId'), files[0], files[1] ]
        }
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Validate file integrity and format
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

    FASTQ_FILE_INTEGRITY (ch_samplesheet_parsed.fastq)
    ch_versions = ch_versions.mix(FASTQ_FILE_INTEGRITY.out.versions)
    ch_integrity_reports = ch_integrity_reports.mix(FASTQ_FILE_INTEGRITY.out.reports)

    BAM_FILE_INTEGRITY (ch_samplesheet_parsed.aln, ch_fasta, ch_fai, ch_dict)
    ch_integrity_reports = ch_integrity_reports.mix(BAM_FILE_INTEGRITY.out.reports)

    VCF_FILE_INTEGRITY (ch_samplesheet_parsed.vcf, ch_intervals, ch_fasta, ch_fai, ch_dict, ch_dbsnp)
    ch_integrity_reports = ch_integrity_reports.mix(VCF_FILE_INTEGRITY.out.reports)

    FILE_INTEGRITY_REPORT(ch_integrity_reports)

    ch_multiqc_files = ch_multiqc_files.mix(FILE_INTEGRITY_REPORT.out.json_report)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    COLLECT SOFTWARE VERSIONS & MultiQC
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

    topic_versions = channel.topic('versions')

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(topic_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name:  'seq-data-validation_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        channel.fromPath(params.multiqc_config, checkIfExists: true) :
        channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
