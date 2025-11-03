process SAMTOOLS_QUICKCHECK {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.21--h96c455f_1':
        'biocontainers/samtools:1.21--h96c455f_1' }"

    input:
    tuple val(meta), path(input), path(index) // channel: [ val(meta), path(bam/cram) ]

    output:
    tuple val(meta), path("*.txt"), emit: txt
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    set +e

    QUICKCHECK_EXIT_CODE=0

    samtools \\
        quickcheck \\
        ${args} \\
        ${input} > ${prefix}.quickcheck.txt 2>&1

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS

    exit 0
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def file_type = input.getExtension()
    """
    touch ${prefix}.samtools_quickcheck.status.yml

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """
}
