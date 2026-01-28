process PARSE_DRAGEN {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1':
        'biocontainers/python:3.9--1' }"

    input:
    tuple val(meta), val(types), path(files, stageAs: "inputs/*", arity:'1..*'), val(oldID), val(newID)

    output:
    tuple val(meta), path("${prefix}/**", type: "file"), optional: true, emit: out_files
    tuple val(meta), path("file_manifest.tsv"), optional: true, emit: manifest
    tuple val(meta), path("*.log"), emit: log
    tuple val(meta), path("*.skipped_files.txt"), optional: true, emit: unprocessed_files
    path "versions.yml"       , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def args = task.ext.args ?: ''
    def file_list = files.join(' ')
    def types_list = types.join(' ')
    """
    parse_dragen_files.py \\
        --new_id ${newID} \\
        --old_id ${oldID} \\
        --types ${types_list} \\
        --files ${file_list} \\
        -o ${prefix} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        parse_dragen_files.py: \$(parse_dragen_files.py --version)
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    for file in inputs/*; do
        touch "\$(basename \$file | sed "s/${oldID}/${newID}/")"
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        parse_dragen_files.py: \$(parse_dragen_files.py --version)
    END_VERSIONS
    """
}
