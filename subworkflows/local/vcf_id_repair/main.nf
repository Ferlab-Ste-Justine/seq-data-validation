include { PARSER_PARSEVCF as PARSE_VCF_HEADER } from '../../../modules/local/header_parser/parsevcf/main'
include { BCFTOOLS_REHEADER    } from '../../../modules/nf-core/bcftools/reheader/main'
include { MD5SUM  } from '../../../modules/nf-core/md5sum/main'

workflow VCF_ID_REPAIR {

    take:
    ch_input // channel: [ mandatory ] meta, vcf, tbi

    main:
    ch_versions = channel.empty()

    ch_vcf_header = ch_input
        .map { meta, vcf, _tbi ->
            [ meta, vcf, meta.old_id, meta.sample ]
        }

    PARSE_VCF_HEADER(ch_vcf_header)

    ch_reheader_input =  PARSE_VCF_HEADER.out.vcf_header
        .map { meta, vcf, new_header ->
            [ meta, vcf, new_header, [] ]
        }

    BCFTOOLS_REHEADER(ch_reheader_input, [[:],[]])
    vcf_tbi = BCFTOOLS_REHEADER.out.vcf
                .join(BCFTOOLS_REHEADER.out.index)

    MD5SUM ( vcf_tbi
        .collect{ _meta, vcf, _tbi -> vcf }
        .map { files -> [ [id: 'variants'], files ] }, false )

    // Gather versions of all tools used
    ch_versions = ch_versions.mix(BCFTOOLS_REHEADER.out.versions.first())
    ch_versions = ch_versions.mix(MD5SUM.out.versions)

    emit:
    vcf_tbi                      // channel: [ val(meta), path(vcf), path(tbi) ]
    checksums = MD5SUM.out.checksum  // channel: [ path(md5sum.txt) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}
