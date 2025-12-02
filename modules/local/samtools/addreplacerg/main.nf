process SAMTOOLS_ADDREPLACERG {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.22.1--h96c455f_0' :
        'biocontainers/samtools:1.22.1--h96c455f_0' }"

    input:
    tuple val(meta), path(input), val(rg_line), val(rgid)

    output:
    tuple val(meta), path("*.{bam,cram}") , emit: bam
    path  "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def rg_arg = rg_line ? "-r $rg_line" : ''
    def rgid_arg = rgid ? "-R $rgid" : ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def file_type = input.getExtension()
    """
    samtools \\
        addreplacerg \\
        $args \\
        $rg_arg \\
        $rgid_arg \\
        -@ ${task.cpus} \\
        -o ${prefix}.${file_type} \\
        $input

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def file_type = input.getExtension()
    """
    echo $args
    touch ${input}.${file_type}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
