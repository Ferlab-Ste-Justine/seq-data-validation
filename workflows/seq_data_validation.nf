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

include { RENAME_FASTQ  } from '../modules/local/rename_fastq/main'
include { VCF_ID_REPAIR  } from '../subworkflows/local/vcf_id_repair/main'
include { BAM_ID_REPAIR  } from '../subworkflows/local/bam_id_repair/main'
include { PARSE_DRAGEN  } from '../modules/local/parse_dragen/main'
include { MD5SUM  } from '../modules/nf-core/md5sum/main'
include { BAM_FILE_INTEGRITY  } from '../subworkflows/local/bam_file_integrity/main'
include { VCF_FILE_INTEGRITY  } from '../subworkflows/local/vcf_file_integrity/main'
include { FASTQ_FILE_INTEGRITY  } from '../subworkflows/local/fastq_file_integrity/main'
include { FILE_INTEGRITY_REPORT  } from '../subworkflows/local/generate_report/main'
include { GENERATE_MANIFEST  } from '../subworkflows/local/generate_manifest/main'

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
    ch_logs = channel.empty()
    ch_multiqc_files = channel.empty()
    ch_per_sample_manifest = channel.empty()

    if (params.replace_sample_id) {
        ch_manifest_files = channel.empty()
    }
    else {
        ch_manifest_files = ch_samplesheet
            .map { meta, files ->
                [ meta, files[0], files[1] ]
            }
    }

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
        remainder: true
            return [ meta - meta.subMap('lane','runId'), files[0] ]
        }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Replace SampleID in BAM/CRAM and VCF/GVCF files
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
    if (params.replace_sample_id)  {
        /*
        -------
        Handle FASTQ files
        -------
        */
        RENAME_FASTQ ( ch_samplesheet_parsed.fastq )
        ch_fastq_out = RENAME_FASTQ.out.fastq
            .map { meta, files ->
                [ meta, files[0], files[1] ] }

        ch_manifest_files = ch_manifest_files
            .mix(ch_fastq_out)

        ch_logs = ch_logs.mix(ch_samplesheet_parsed.fastq
            .join( RENAME_FASTQ.out.fastq )
            .map { meta, fastqs, renamed_fastqs ->
                def same_name = fastqs[0].getName() == renamed_fastqs[0].getName()
                if ( same_name ) {
                    def log_msg = "INFO - No renaming needed for ${meta.fileType} - ${meta.sample}: ${fastqs[0].getName()}, ${fastqs[1].getName()}. File copied as is."
                    return [ meta, log_msg ]
                }
                def log_msg = "INFO - Successfully renamed ${meta.fileType} - ${meta.sample}: ${fastqs[0].getName()}, ${fastqs[1].getName()} -> ${renamed_fastqs[0].getName()}, ${renamed_fastqs[1].getName()}"
                return [ meta, log_msg ]
            }
        )


        /*
        -------
        Handle VCF files
        ------
        */
        VCF_ID_REPAIR ( ch_samplesheet_parsed.vcf )
        ch_versions = ch_versions.mix(VCF_ID_REPAIR.out.versions)
        ch_manifest_files = ch_manifest_files.mix(VCF_ID_REPAIR.out.vcf_tbi)
        ch_logs = ch_logs.mix(VCF_ID_REPAIR.out.logs)

        /*
        -------
        Handle BAM/CRAM files
        ------
        */
        BAM_ID_REPAIR ( ch_samplesheet_parsed.aln, ch_fasta )
        ch_versions = ch_versions.mix(BAM_ID_REPAIR.out.versions)
        ch_manifest_files = ch_manifest_files.mix(BAM_ID_REPAIR.out.bam_bai)
        ch_logs = ch_logs.mix(BAM_ID_REPAIR.out.logs)

        /*
        -------
        Handle other files (e.g., metrics, logs, tsv, csv files)
        ------
        */

        // group by sample
        ch_other_files = ch_samplesheet_parsed.remainder
            .map { meta, file ->
                [meta - meta.subMap('file_id','fileType','count'), meta.fileType, file] }
            .groupTuple()
            .map { meta, types_list, files ->
                def oldID = meta.old_id
                def newID = meta.sample
                tuple( meta, types_list, files, oldID, newID )
            }

        PARSE_DRAGEN( ch_other_files )
        ch_per_sample_manifest = ch_per_sample_manifest.mix(PARSE_DRAGEN.out.manifest)

        ch_logs
            .map { meta, log_msg ->
                def new_meta = meta.subMap('id','participant','sample','old_id','count')
                [ new_meta, log_msg ]
            }
            .groupTuple()
            .collectFile(storeDir: "${params.outdir}/results") { meta, log_msgs ->
                new File("${params.outdir}/results/${meta.id}/logs").mkdirs()
                def filename = "${meta.id}/logs/${meta.sample}.sample_rename.seq_data.log"
                def date = new java.util.Date()
                def loginfo_str = "${date} - INFO - Replaced sample ID in data files for sample ${meta.sample} (old ID: ${meta.old_id})\nINFO - Processing ${meta.count} file (pairs)..."
                return [ filename , loginfo_str + "\n" + log_msgs.join("\n") ]
            }

    }

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Validate file integrity and format
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
    ch_in_validation_fq = params.replace_sample_id ? RENAME_FASTQ.out.fastq : ch_samplesheet_parsed.fastq
    FASTQ_FILE_INTEGRITY (ch_in_validation_fq)
    ch_versions = ch_versions.mix(FASTQ_FILE_INTEGRITY.out.versions)

    ch_in_validation_aln = params.replace_sample_id ? BAM_ID_REPAIR.out.bam_bai : ch_samplesheet_parsed.aln
    BAM_FILE_INTEGRITY (ch_in_validation_aln, ch_fasta, ch_fai, ch_dict)

    ch_in_validation_vcfs = params.replace_sample_id ? VCF_ID_REPAIR.out.vcf_tbi : ch_samplesheet_parsed.vcf
    VCF_FILE_INTEGRITY (ch_in_validation_vcfs, ch_intervals, ch_fasta, ch_fai, ch_dict, ch_dbsnp)

    ch_integrity_reports = ch_integrity_reports
        .mix(FASTQ_FILE_INTEGRITY.out.reports)
        .mix(BAM_FILE_INTEGRITY.out.reports)
        .mix(VCF_FILE_INTEGRITY.out.reports)

    FILE_INTEGRITY_REPORT(ch_integrity_reports)

    ch_multiqc_files = ch_multiqc_files.mix(FILE_INTEGRITY_REPORT.out.json_report)

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    MANIFEST
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

    ch_others_manifest = ch_per_sample_manifest
            .map { meta, manifest ->
                [ meta.subMap('id','participant','sample','old_id'), manifest ]
            }

    ch_manifest_input = ch_manifest_files
        .map { meta, file1, file2 ->
            [ meta.subMap('id','participant','sample','count','old_id'), meta.fileType, file1, file2 ]
            }
        .map { meta, type, file1, file2 ->
            def key = groupKey(meta - meta.subMap('count'), meta.count)
                [key, type, file1, file2]
            }
        .groupTuple()
        .map { key, types_list, files1, files2 ->
            [ key.getGroupTarget(), types_list, files1, files2 ]
        }
        .join( ch_others_manifest, remainder: true )

    GENERATE_MANIFEST ( ch_manifest_input )

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

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]


}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
