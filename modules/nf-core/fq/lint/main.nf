process FQ_LINT {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/fq:0.12.0--h9ee0642_0':
        'biocontainers/fq:0.12.0--h9ee0642_0' }"

    input:
    tuple val(meta), path(fastq)

    output:
    tuple val(meta), path("*.fq_lint.txt"), emit: lint
    path "versions.yml"                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    set +e
    FQLINT_EXIT_CODE=0

    # log is written to stdout, error to stderr when --lint-mode panic (default)
    fq lint \\
        $args \\
        $fastq > ${prefix}.fq_lint.txt

    FQ_LINT_EXIT_CODE=\$?
    if [ \$FQ_LINT_EXIT_CODE -ne 0 ]; then
        if [ \$FQ_LINT_EXIT_CODE -ne 1 ]; then
            exit \$FQ_LINT_EXIT_CODE
        fi
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fq: \$(echo \$(fq lint --version | sed 's/fq-lint //g'))
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.fq_lint.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fq: \$(echo \$(fq lint --version | sed 's/fq-lint //g'))
    END_VERSIONS
    """
}
