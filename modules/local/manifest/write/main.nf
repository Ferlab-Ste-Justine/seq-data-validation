process WRITE_MANIFEST {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/python:3.9--1':
        'biocontainers/python:3.9--1' }"

    input:
    tuple val(meta), val(types), path(files)
    output:
    tuple val(meta), path("*_manifest.tsv"), emit: manifest
    path "versions.yml"       , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def file_list = files.join(' ')
    def types_list = types.join(' ')
    """
    write_manifest.py \\
        --types ${types_list} \\
        --files ${file_list} \\
        -o ${prefix}_manifest.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        write_manifest.py: \$(write_manifest.py --version)
    END_VERSIONS
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "Filename\tSize\tMD5\tfileType\n" > ${prefix}_manifest.tsv
    echo "sample1.fastq\t0\td41d8cd98f00b204e9800998ecf8427e\tFASTQ\n" >> ${prefix}_manifest.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        write_manifest.py: \$(write_manifest.py --version)
    END_VERSIONS
    """
}
