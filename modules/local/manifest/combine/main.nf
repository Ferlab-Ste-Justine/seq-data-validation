process COMBINE_MANIFESTS {
    tag "${meta.id}"
    label 'process_single'

    input:
    tuple val(meta), path(manifest_omics), path(manifest_others)

    output:
    tuple val(meta), path("manifest_${prefix}.tsv"), emit: manifest

    script:
    prefix = task.ext.prefix ?: "${meta.id}"
    def manifest_others_cmd = manifest_others ? "<(sed 1d ${manifest_others})": ''
    """
    cat ${manifest_omics} ${manifest_others_cmd} > manifest_${prefix}.tsv
    """

    stub:
    prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo "sample_id\tfile_name\tfile_size\tfile_md5sum\tfile_type\n" > manifest_${prefix}.tsv
    """
}
