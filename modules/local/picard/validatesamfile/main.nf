process PICARD_VALIDATESAMFILE {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/picard:3.4.0--hdfd78af_0':
        'biocontainers/picard:3.4.0--hdfd78af_0' }"

    input:
    tuple val(meta), path(bam), path(bai)
    tuple val(meta2), path(fasta)
    tuple val(meta3), path(fai)
    tuple val(meta4), path(dict)

    output:
    tuple val(meta), path("*hist.txt"), emit: hist
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def reference_file = fasta ? "--REFERENCE_SEQUENCE ${fasta}" : ""

    def avail_mem = 3072
    if (!task.memory) {
        log.info '[Picard ValidateSamFile] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.'
    } else {
        avail_mem = (task.memory.mega*0.8).intValue()
    }

    """
    set +e

    picard \\
        -Xmx${avail_mem}M \\
        ValidateSamFile \\
        ${args} \\
        ${reference_file} \\
        --INPUT ${bam} \\
        --OUTPUT ${prefix}.hist.txt \\
        --TMP_DIR .

    VALIDATESAMFILE_EXIT_CODE=\$?

    # Handle exit codes not related to invalid SAM/BAM files
    if [ \$VALIDATESAMFILE_EXIT_CODE -ne 0 ]; then
        # If exit code is not 1, 2, or 3, then it is a failure, exit with that error code
        if [ \$VALIDATESAMFILE_EXIT_CODE -ne 1 ] && [ \$VALIDATESAMFILE_EXIT_CODE -ne 2 ] && [ \$VALIDATESAMFILE_EXIT_CODE -ne 3 ]; then
            exit \$VALIDATESAMFILE_EXIT_CODE
        fi
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        picard: \$(picard ValidateSamFile --version 2>&1 | grep -o 'Version:.*' | cut -f2- -d:)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}.hist.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        picard: \$(picard ValidateSamFile --version 2>&1 | grep -o 'Version:.*' | cut -f2- -d:)
    END_VERSIONS
    """
}
