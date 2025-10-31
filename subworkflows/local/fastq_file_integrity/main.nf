include { FQ_LINT                } from '../../../modules/nf-core/fq/lint/main'
include { SEQFU_CHECK            } from '../../../modules/local/seqfu/check/main'

workflow FASTQ_FILE_INTEGRITY {
    take:
    ch_fastq  // channel: [ val(meta), fastq1, fastq2 ]

    main:
    ch_versions = channel.empty()

    SEQFU_CHECK ( ch_fastq )

    FQ_LINT ( ch_fastq )
    ch_versions = ch_versions.mix(FQ_LINT.out.versions)

    ch_reports = ch_fastq
        .join(SEQFU_CHECK.out.check)
        .join(FQ_LINT.out.lint)
        .map { meta, fqfiles, out_sfc, out_fql ->
            [ meta, fqfiles[0], fqfiles[1], [
                [ process:'seqfu_check', output:out_sfc], 
                [ process:'fq_lint', output:out_fql]
            ]]
        }

    emit:
    reports  = ch_reports                       // channel: [ *.tsv, *.html, *.zip ]
    versions = ch_versions                     // channel: [ versions.yml ]
}
