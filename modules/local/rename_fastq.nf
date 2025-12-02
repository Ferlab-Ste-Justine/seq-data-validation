process RENAME_FASTQ {
    tag "${meta.id}"
    label 'process_single'

    input:
    tuple val(meta), path(fastq_files)

    output:
    tuple val(meta), path(fastq_files), emit:fastq_old
    tuple val(meta),  path("*fastq*"), optional: true, emit:fastq_dummy

    script:
    def new_files = fastq_files
        .collect { fq -> fq.name.replace("${meta.old_id}", "${meta.sample}") }
        .join(' ')
    """
    # Will do nothing if file exists
    touch ${new_files}
    """
}
