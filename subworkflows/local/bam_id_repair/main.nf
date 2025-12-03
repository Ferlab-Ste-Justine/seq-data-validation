//
// Workflow that checks if internal sampleID in BAM/CRAM matches with sample_registration id and renames sampleid if not
//
include { SAMTOOLS_SAMPLES as SAMTOOLS_SAMPLES_RGID } from '../../../modules/local/samtools/samples/main'
include { SAMTOOLS_INDEX     } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_REHEADER } from '../../../modules/local/samtools/reheader/main'
include { PARSER_PARSEBAM  as PARSE_BAM_HEADER } from '../../../modules/local/header_parser/parsebam/main'
include { SAMTOOLS_ADDREPLACERG } from '../../../modules/local/samtools/addreplacerg/main'
include { MD5SUM  } from '../../../modules/nf-core/md5sum/main'

workflow BAM_ID_REPAIR {

    take:
    ch_input // channel: [ mandatory ] meta, bam/cram, bai/crai

    main:
    ch_versions = channel.empty()

    ch_bam_header = ch_input
        .map { meta, bam, _bai ->
            [ meta, bam, meta.old_id, meta.sample ]
        }

    PARSE_BAM_HEADER(ch_bam_header)

    ch_branch = ch_input
        .join(PARSE_BAM_HEADER.out.rg_line, remainder: true)
        .map { meta, bam, _bai, rg_line ->
            [ meta, bam, rg_line ]
        }
        .branch { meta, bam, rg_line ->
            change_rgid: rg_line
                def rg_lines = rg_line.readLines()
                if (rg_lines.size() > 1) {
                    log.warn "Multiple RGIDs found in ${bam} (id: ${meta.id}). Replacing multiple RGIDs in the same file is not yet supported. Assigning all reads to the first one."
                }
                def rg_val = rg_lines.first().strip().split('\t')[1]
                [ meta, bam, rg_val ]
                return [ meta, bam, rg_val, [] ]
            direct: true
                return [ meta, bam ]
        }

    SAMTOOLS_ADDREPLACERG(ch_branch.change_rgid)

    // create input to samtools reheader
    ch_reheader_input = ch_branch.direct
        .mix( SAMTOOLS_ADDREPLACERG.out.bam )
        .join( PARSE_BAM_HEADER.out.header )

    // Replace header in bam/cram
    SAMTOOLS_REHEADER(ch_reheader_input)

    // index new reheaded file
    SAMTOOLS_INDEX(SAMTOOLS_REHEADER.out.bam)

    index_ch = SAMTOOLS_INDEX.out.bai
        .mix(SAMTOOLS_INDEX.out.crai)
        .mix(SAMTOOLS_INDEX.out.csi)

    bam_bai = SAMTOOLS_REHEADER.out.bam
                .join( index_ch )

    MD5SUM ( bam_bai
        .collect{ _meta, bam, _bai -> bam }
        .map { files -> [ [id: 'mapped_reads'], files ] }, false )

    // Gather versions of all tools used
    ch_versions = ch_versions.mix(SAMTOOLS_INDEX.out.versions.first())
    ch_versions = ch_versions.mix(MD5SUM.out.versions)

    emit:
    bam_bai                     // channel: [ val(meta), path(bam/cram), path(bai/crai) ]
    checksums = MD5SUM.out.checksum  // channel: [ path(md5sum.txt) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}
