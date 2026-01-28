# Ferlab-Ste-Justine/seq-data-validation: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### `Fixed`

- [#21](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/21) Fix validate that all samples in the samplesheet are present in the id_mapping file when replacing sample IDs.
- [#20](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/20) Fix parsing error when VCF has no GTs/sampleID.

## v1.0.0 - [18/12/25]

### `Added`

- [#17](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/17) Output log files for sample ID replacement modules

- [#15](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/15) Workflow and modules to output file manifest

- [#12](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/12) Add support for parsing additional file formats in the parse_dragen module

- [#11](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/11) Add modules to compute md5sum for renamed fastq and repaired bam/cram files

- [#10](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/10) Add modules and workflows to replace sampleID in vcf and bam/cram and rename fastq files

### `Fixed`

- [#13](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/13) Fix bug in parse_bam_header

### `Dependencies`

- [#12](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/12) Input schema modified to accept multiple files for the parse_dragen module

## v0.1.0

### `Added`

- [#8](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/6) Main workflow and generation of JSON report

- [#6](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/6) VCF/GVCF validation workflow

- [#4](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/4) BAM/CRAM validation workflow

- [#3](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/3) FASTQ validation workflow

### `Fixed`

### `Dependencies`

- [#9](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/9) Update documentation

- [#7](https://github.com/Ferlab-Ste-Justine/seq-data-validation/pull/7) Updated samplesheet and parsing

### `Deprecated`
