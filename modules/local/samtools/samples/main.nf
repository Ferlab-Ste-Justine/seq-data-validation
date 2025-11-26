process SAMTOOLS_SAMPLES {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.22.1--h96c455f_0' :
        'biocontainers/samtools:1.22.1--h96c455f_0' }"

    input:
    tuple val(meta), path(input), path(idx) // channel: [ val(meta), path(bam/cram) ]
    val(rgtag)
    path(fasta) // optional
    path(references_file) // optional

    output:
    tuple val(meta), path("*.${suffix}"), emit: output
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def tag_line = rgtag ? "-T ${rgtag}" : ""
    def prefix = task.ext.prefix ?: "${meta.id}"
    suffix = task.ext.suffix ?: "samples.txt"
    def reference_list_arg = references_file ? "-F ${references_file}" : ""
    def reference_arg = fasta ? "-f ${fasta}" : ""
    """
    samtools \\
        samples \\
        $args \\
        $tag_line \\
        $reference_arg \\
        $reference_list_arg \\
        -o ${prefix}.${suffix} \\
        $input

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    suffix = task.ext.suffix ?: "samples.txt"
    """
    echo -e "sample\tpath" > ${prefix}.${suffix}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """
}
