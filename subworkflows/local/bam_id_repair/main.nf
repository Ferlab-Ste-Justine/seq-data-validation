//
// Workflow that checks if internal sampleID in BAM/CRAM matches with sample_registration id and renames sampleid if not
//
include { SAMTOOLS_SAMPLES     } from '../../../modules/local/samtools/samples/main'
include { SAMTOOLS_SAMPLES as SAMTOOLS_SAMPLES_RGID } from '../../../modules/local/samtools/samples/main'
include { SAMTOOLS_INDEX     } from '../../../modules/nf-core/samtools/index/main'
include { SAMTOOLS_REHEADER } from '../../../modules/local/samtools/reheader/main'
include { PARSER_PARSEBAM  as PARSE_BAM_HEADER } from '../../../modules/local/header_parser/parsebam/main'

workflow BAM_ID_REPAIR {

    take:
    ch_input // channel: [ mandatory ] meta, bam/cram, bai/crai
    ch_fasta // channel: [ optional ]

    main:
    ch_versions = channel.empty()

    // Get RGID from BAM/CRAM
    SAMTOOLS_SAMPLES_RGID(ch_input, "ID", ch_fasta, [])

    branched_bams = ch_input
        .join(SAMTOOLS_SAMPLES_RGID.out.output)
            .map{ meta, bam, bai, query_RGID ->
                assert query_RGID.countLines() < 2 : 'More than one RGID in bam file'
                def rgid = query_RGID.text.split().first()
                // check if sample oldID is in rgid
                def oldID_in_rg = rgid.contains(meta.old_id)
                [ meta, bam, bai, rgid, oldID_in_rg ]
            }
            .view()
            .branch { meta, bam, bai, rgid, oldID_in_rg ->
                reheader: (rgid != meta.participant_sample) && params.skip_reheader == false
                direct: (rgid == meta.participant_sample) || params.skip_reheader == true
            }

    ch_bam_header = ch_input
        .map { meta, bam, _bai ->
            [ meta, bam, meta.old_id, meta.sample ]
        }

    PARSE_BAM_HEADER(ch_bam_header)

    // create input to vcf reheader option --samples
    ch_reheader_input =  ch_input
        .join( PARSE_BAM_HEADER.out.header )
        .map { meta, bam, _bai, new_bam_header ->
            [ meta, bam, new_bam_header ]
        }

    // PARSE_BAM_HEADER.out.replace_rg.view()

    // Edit Sample ID and header in bam/cram
    SAMTOOLS_REHEADER(ch_reheader_input)

    // index new reheaded file
    SAMTOOLS_INDEX(SAMTOOLS_REHEADER.out.bam)

    index_ch = SAMTOOLS_INDEX.out.bai
        .mix(SAMTOOLS_INDEX.out.crai)
        .mix(SAMTOOLS_INDEX.out.csi)

    bam_bai = SAMTOOLS_REHEADER.out.bam
                .join( index_ch )
                // .mix( branched_bams.direct
                //         .map { meta, bam, idx, _sample_name ->
                //         [ meta, bam, idx ] } )

    // Gather versions of all tools used
    ch_versions = ch_versions.mix(SAMTOOLS_INDEX.out.versions.first())

    emit:
    bam_bai                     // channel: [ val(meta), path(bam/cram), path(bai/crai) ]
    versions = ch_versions       // channel: [ path(versions.yml) ]
}
