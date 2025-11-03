include { SAMTOOLS_QUICKCHECK     } from '../../../modules/local/samtools/quickcheck/main'
include { PICARD_VALIDATESAMFILE  } from '../../../modules/local/picard/validatesamfile/main'

workflow BAM_FILE_INTEGRITY {
    take:
    ch_aln      // channel: [ val(meta), path(bam/cram), path(bai/crai/csi) ]
    ch_fasta    // [optional] path: fasta
    ch_fai      // [optional] path: fai
    ch_dict     // [optional] path: dict

    main:

    SAMTOOLS_QUICKCHECK(ch_aln)

    PICARD_VALIDATESAMFILE( ch_aln, ch_fasta.map { it -> [[id: 'fasta'], it] }, ch_fai.map { it -> [[id: 'fai'], it] }, ch_dict.map { it -> [[id: 'dict'], it] })

    ch_reports = ch_aln
        .join( SAMTOOLS_QUICKCHECK.out.txt )
        .join( PICARD_VALIDATESAMFILE.out.hist )
        .map { meta, bam, bai, out_sqc, out_pvs ->
            [ meta, bam, bai, [
                [ process:'samtools_quickcheck', output:out_sqc],
                [ process:'picard_validatesamfile', output:out_pvs]
            ]]
        }

    emit:
    reports  = ch_reports                       // channel: [ meta, bam, bai, checks ]
}
