include { GATK4_VALIDATEVARIANTS  } from '../../../modules/local/gatk4/validatevariants/main'

workflow VCF_FILE_INTEGRITY {
    take:
    ch_vcf  // channel: [ val(meta), vcf, idx ]
    ch_intervals // channel: path intervals
    ch_fasta // channel: path fasta
    ch_fai // channel: path fai
    ch_dict // channel: path dict
    ch_dbsnp // channel: path dbsnp

    main:

    ch_vcf_intervals = ch_vcf.map { meta, vcf, tbi ->
        def intervals = ch_intervals.empty ? [] : ch_intervals
        return [ meta, vcf, tbi, intervals  ]
    }

    GATK4_VALIDATEVARIANTS ( ch_vcf_intervals,
        ch_fasta,
        ch_fai,
        ch_dict,
        ch_dbsnp
    )

    ch_reports = ch_vcf
        .join(GATK4_VALIDATEVARIANTS.out.txt)
        .map { meta, vcf, tbi, out_gvv ->
            [ meta, vcf, tbi, [
                [ process:'gatk4_validatevariants', output:out_gvv]
            ]]
        }

    emit:
    reports  = ch_reports                       // channel: [ meta, vcf, tbi, [ [ process, output ] ] ]
}
