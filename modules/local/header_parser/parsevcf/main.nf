process PARSER_PARSEVCF {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/pysam:0.23.3--py310h64e62c9_1':
        'biocontainers/pysam:0.23.3--py310h64e62c9_1' }"

    input:
    tuple val(meta), path(vcf), val(oldID), val(newID)

    output:
    tuple val(meta), path(vcf), path("*.{vcf,txt}"), emit: vcf_header
    path "versions.yml"           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    vcf_parse_header.py \\
        --new_id $newID \\
        --old_id $oldID \\
        -o ${prefix}.new.header.vcf \\
        $vcf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcf_parse_header.py: \$(vcf_parse_header.py --version)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo $args

    touch ${prefix}.new.header.vcf

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        vcf_parse_header.py: \$(vcf_parse_header.py --version)
    END_VERSIONS
    """
}
