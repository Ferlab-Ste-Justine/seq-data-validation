process PARSER_PARSEBAM {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pysam:0.23.3--py310h64e62c9_1':
        'biocontainers/pysam:0.23.3--py310h64e62c9_1' }"

    input:
    tuple val(meta), path(bam), val(oldID), val(newID)

    output:
    tuple val(meta), path("*.{sam,txt}"), emit: header
    // tuple val(meta), env("REPLACE_RG"), emit: replace_rg
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    bam_parse_header.py \\
        --new_id ${newID} \\
        --old_id ${oldID} \\
        -o ${prefix}.new.header.sam \\
        $bam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bam_parse_header.py: \$(bam_parse_header.py --version)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo $args

    touch ${prefix}.new.header.sam

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bam_parse_header.py: \$(bam_parse_header.py --version)
    END_VERSIONS
    """
}
