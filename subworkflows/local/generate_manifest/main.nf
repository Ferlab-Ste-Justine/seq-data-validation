include { WRITE_MANIFEST  } from '../../../modules/local/manifest/write/main'
include { COMBINE_MANIFESTS  } from '../../../modules/local/manifest/combine/main'

workflow GENERATE_MANIFEST {
    take:
    ch_files  // channel: [ val(meta), types, files1, files2, others_manifest ]
    main:
    ch_versions = channel.empty()

    ch_files
        .multiMap { meta, types, files1, files2, others_manifest ->
            others: [meta, others_manifest]
            files: [meta, types, files1, files2]
        }
        .set { ch_files_split}

    ch_files_split.files
        .transpose()
        .map { meta, type, file1, file2 ->
            def suffix = file2 ? (file2.name.toString() - '.gz').tokenize('.').last() : null
            def type2 = suffix ? (type == "FASTQ" ? type : suffix.toUpperCase()) : null
            [meta, file2 ? [type, type2] : [type], file2 ? [file1, file2] : [file1] ]
        }
        .transpose()
        .groupTuple()
        .set{ch_files_input}

    WRITE_MANIFEST(ch_files_input)

    ch_input_cat = WRITE_MANIFEST.out.manifest
        .join( ch_files_split.others , remainder: true )
        .map { meta, manifest_omics, manifest_others ->
            [ meta, manifest_omics, manifest_others?: [] ]
        }

    COMBINE_MANIFESTS(ch_input_cat)

    emit:
    manifest = COMBINE_MANIFESTS.out.manifest   // channel: [ manifest_*.tsv ]
}
