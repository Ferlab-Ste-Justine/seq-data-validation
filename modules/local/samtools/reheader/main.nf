process SAMTOOLS_REHEADER {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/samtools:1.21--h96c455f_1':
        'biocontainers/samtools:1.21--h96c455f_1' }"

    input:
    tuple val(meta), path(input), path(header) // channel: [ val(meta), path(bam/cram), path(header) ]

    output:
    tuple val(meta), path("*.{bam,cram}"), emit: bam
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    if (args.contains('-i') || args.contains('--in-place')) error "In-place reheadering is not supported. Please provide an output prefix different from the input file name."
    if (header && (args.contains ("-c") || args.contains("--command")))  error "--command and header input cannot be used together. Please provide only one of these options."
    def prefix = task.ext.prefix ?: "${meta.id}"
    def file_type = input.getExtension()
    if ("$input" == "${prefix}.${file_type}") error "Input and output names are the same, set prefix in module configuration to disambiguate!"
    """
    samtools \\
        reheader \\
        $args \\
        $header \\
        $input > ${prefix}.${file_type}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    if (args.contains('-i') || args.contains('--in-place')) error "In-place reheadering is not supported. Please provide an output prefix different from the input file name."
    if (header && (args.contains ("-c") || args.contains("--command")))  error "--command and header input cannot be used together. Please provide only one of these options."
    def prefix = task.ext.prefix ?: "${meta.id}"
    def file_type = input.getExtension()
    if ("$input" == "${prefix}.${file_type}") error "Input and output names are the same, set prefix in module configuration to disambiguate!"
    """
    touch ${prefix}.${file_type}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version |& sed '1!d ; s/samtools //')
    END_VERSIONS
    """
}
