# Ferlab-Ste-Justine/seq-data-validation: System Requirements

## Software Requirements

VM will need to have installed

- Nextflow 24.10 - requires Bash 3.2 (or later) and Java 17 (or later, up to 25)
- Docker or apptainer

## Configuration

> When you launch a pipeline script, Nextflow detects configuration files from multiple sources and applies them in the following order (from lowest to highest priority):
>
> 1. $NXF_HOME/config (defaults to $HOME/.nextflow/config)
> 2. nextflow.config in the project directory
> 3. nextflow.config in the launch directory
> 4. Config files specified with -c <config-files>

Nextflow config file provides execution details, s3 endpoint, and (optionally) credentials (see below).

Example of nextflow.config for local execution with s3 storage:

```json nextflow.config
workDir = '<path to scratch directory>'

process {
    executor = 'local'
}
docker {
    enabled = true
    runOptions = '-u $(id -u):$(id -g)'
}
aws {
    [accessKey = '<Your access key>']
    [secretKey = '<Your secret key>']
    client {
        endpoint = '<Your storage endpoint URL>'
        s3PathStyleAccess = true
    }
}
```

<details>
    <summary>About how nextflow finds S3 credentials:</summary>

1. From the nextflow.config file (as shown above)
2. The environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
3. The environment variables `AWS_ACCESS_KEY` and `AWS_SECRET_KEY`
4. The profile in the AWS credentials file located at `~/.aws/credentials`
   - Uses the `default` profile or the environment variable `AWS_PROFILE` if set
5. The profile in the AWS client configuration file located at `~/.aws/config`
   - Uses the `default` profile or the environment variable `AWS_PROFILE` if set
6. The temporary AWS credentials provided by an IAM instance role. See [IAM Roles](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)documentation for details.

</details>

## Storage Requirements

Input data can be read directly from an S3 bucket or other cloud storage. Likewise, output data can be written to cloud storage (See [Usage](usage.md)). The pipeline requires a working directory (scratch) to store intermediate files during execution.

- It is recommended to use fast storage for the working directory to improve performance. **In case of execution in a CQDG Virtual Machine, the provided CephFS storage space must be used as working directory.**
- Work dir can be set in the nextflow.config file via the `workDir` value, or at runtime using the `-w` or `--work-dir` Nextflow command-line options. i.e. `workDir = /cephfs/<your_user>/nextflow/scratch`.

**Sequence data validation only**

The working directory should have an available storage of _1x the size of the input data + 5GB_ to accommodate the staging of input files as well as the intermediate and output files.

**Sample ID replacement module**

The working directory should have an available storage of _minimum 2x the size of the input data + 5GB_ to accommodate the stagging of input files as well as the intermediate and output files.

> [!NOTE] If Read Group IDs (RGIDs) need to be replaced in BAM/CRAM files, the minimum required storage is **3x the size of the CRAM/BAM files plus 2x the size of other files**.

To verify if RGID needs to be replaced in your files run:

    samtools samples -T ID <input.bam/cram> | grep <old_sample_id>

If no output is produced, RGID does not need to be replaced.

Note that currently replacing multiple RGIDs in a single BAM/CRAM file is not supported. If multiple RGIDs are present, all reads will be assigned to the first read group only.

### Container Images

Container images take around **5 GB** of local storage. All images are available in biocontainers and are pulled only once.

The following containerized software are used in this pipeline:

- Multiqc
- Pysam
- samtools
- picard
- gatk4
- bcftools
- seqfu
- fq

Images are pulled automatically at runtime when using Docker or Singularity/Apptainer executors. There is no need to manually download them.

## Hardware Requirements

A test run on a data package of 8 files from the same sample (1 CRAM, 1 gVCF, and 6 small VCFs) was performed on a virtual machine with the following resource limits: 4 CPUs and 8GB of RAM. Data was read from and written to an S3 bucket, with a `cephfs` volume used as the working directory.

Based on this, the following are general hardware recommendations.

### CPU

The most CPU-intensive task is modifying the gVCF header, which can utilize up to 2.6 CPUs. Other validation processes typically use at least 1 CPU. A minimum of **4 CPUs** is recommended for efficient processing.

### Memory

Memory usage varies by process:

- **VCF validation**: 250MB to 800MB, depending on file size.
- **ID replacement**: Approximately 20MB per process.

A minimum of **8GB of RAM** is recommended to comfortably handle a typical sample.

### Runtime

For a single sample, the total processing time is approximately **1.5 minutes**, excluding the time required for data staging from and to S3. Runtimes will vary based on the size and number of input files.
