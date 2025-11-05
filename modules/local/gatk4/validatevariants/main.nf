process GATK4_VALIDATEVARIANTS {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/gatk4:4.5.0.0--py36hdfd78af_0':
        'biocontainers/gatk4:4.5.0.0--py36hdfd78af_0' }"

    input:
    tuple val(meta), path(input), path(input_tbi), path(intervals)
    path(fasta)
    path(fai)
    path(dict)
    path(dbsnp)

    output:
    tuple val(meta), path("*.txt"), emit: txt
    path "versions.yml"           , topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    def gvcf_command = input.name.contains(".gvcf") || input.name.contains(".g.vcf") ? "--validate-GVCF" : ""
    def interval_command = intervals ? "--intervals $intervals" : ""
    def reference_command = fasta ? "--reference $fasta" : ""
    def dbsnp_command = dbsnp ? "--dbsnp $dbsnp" : ""

    def avail_mem = 3072
    if (!task.memory) {
        log.info '[GATK ValidateVariants] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.'
    } else {
        avail_mem = (task.memory.mega*0.8).intValue()
    }
    """
    set +e

    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        ValidateVariants \\
        --variant $input \\
        ${args} \\
        $reference_command \\
        $gvcf_command \\
        $interval_command \\
        $dbsnp_command \\
        --tmp-dir . 2> ${prefix}.txt

    VALIDATEVARIANTS_EXIT_CODE=\$?

    # Handle exit codes not related to invalid VCF files
    if [ \$VALIDATEVARIANTS_EXIT_CODE -ne 0 ]; then
        # exit code 2 is user exception - used for invalid vcf, else exit with that error code
        if [ \$VALIDATEVARIANTS_EXIT_CODE -ne 2 ]; then
            exit \$VALIDATEVARIANTS_EXIT_CODE
        fi
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    echo $args

    touch ${prefix}.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        gatk4: \$(echo \$(gatk --version 2>&1) | sed 's/^.*(GATK) v//; s/ .*\$//')
    END_VERSIONS
    """
}
