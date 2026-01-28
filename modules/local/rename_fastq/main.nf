process RENAME_FASTQ {
    tag "${meta.id}"
    label 'process_single'

    input:
    tuple val(meta), path(fastq_files)

    output:
    tuple val(meta), path("*fastq*", includeInputs: true), emit: fastq

    script:
    """
    # Process to rename staged FASTQ files for downstream use
    for fq in ${fastq_files.join(' ')}; do
        base_name=\$(basename \$fq)
        new_name="\${base_name/${meta.old_id}/${meta.sample}}"
        if [[ \$new_name != *"${meta.sample}"* ]]; then
            new_name="${meta.sample}.\$new_name"
        fi
        mv --no-copy -n \$fq \$new_name || true
    done
    """
}
