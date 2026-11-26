# Development journal

Known issues and notes to follow up on.

## 2026-11-25 – Manifest generation may crash for samples with only "other" files

**Status:** Suspected, not confirmed on a real run. Not fixed (found while working on BIOINFO-252).

**Where:** `workflows/seq_data_validation.nf`, MANIFEST section (`ch_manifest_input` → `GENERATE_MANIFEST`).

**What:** `ch_manifest_input` is built by grouping the FASTQ/BAM/VCF files per sample, then running `.join(ch_others_manifest, remainder: true)` with the `PARSE_DRAGEN` manifests. When a sample has no FASTQ/BAM/VCF entry, the join emits `[meta, null, others_manifest]` (3 elements) instead of `[meta, types, files1, files2, others_manifest]` (5 elements). `GENERATE_MANIFEST` destructures 5 elements, so the pipeline fails with:

```
Invalid method invocation `doCall` with arguments: [[id:456, ...], null, .../file_manifest.tsv]
```

**Seen when:** a `-stub` run aborted early (unrelated error) so the BAM/VCF manifest entries never arrived, while `PARSE_DRAGEN` had already emitted its manifest. The same shape should occur in a normal run for a sample whose samplesheet rows are all "other" file types (CSV, JSON, metrics, …) with `--replace_sample_id`.

**To confirm:** run with `--replace_sample_id` and a samplesheet where one sample only has "other" files (e.g. a single CSV row).

**Possible fix:** after the join, pad missing values, e.g.
`.map { meta, types, files1, files2, others -> ... }` handling the 3-element case, or emit `[meta, [], [], [], others]` for samples with no genomic files. `WRITE_MANIFEST` would also need to accept an empty file list (or be skipped) for those samples.

## 2026-11-26 – Local module/subworkflow nf-tests are out of date

**Status:** Pre-existing, not fixed (found while working on BIOINFO-252). To address in a separate ticket.

**Context:** `scripts/run-test-suite.sh` step 5 runs `nf-test test --profile +docker`, i.e. **every** `.nf.test` in the repo. CI (`.github/workflows/nf-test.yml` → `.github/actions/nf-test/action.yml`) runs `nf-test test --tag pipeline --changed-since HEAD^`, so it only runs tests tagged `pipeline` (only `tests/default.nf.test` is) that relate to the files a PR touches. As a result, the tests under `modules/local/**/tests/` and `subworkflows/local/**/tests/` never run in CI, and most haven't been updated since Nov–Dec 2025 while their modules kept changing. Locally, step 5 therefore fails on tests unrelated to the current branch. `tests/default.nf.test` (the full-pipeline test) is the one nf-test selects with `--changed-since main` for a typical branch.

**Failing tests and causes:**

| Test                                   | Cause                                                                                                                                                                                                                                                                                             |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `modules/local/bcftools/head`          | Passes a `.bam` (`test.paired_end.sorted.bam`) to `bcftools head`, which needs a VCF/BCF.                                                                                                                                                                                                         |
| `modules/local/header_parser/parsevcf` | Same: passes a `.bam` to `vcf_parse_header.py`.                                                                                                                                                                                                                                                   |
| `modules/local/header_parser/parsebam` | Test meta has no old/new IDs, so the command gets `--old_id null --new_id null` and the script raises `RGSM record does not match any given IDs`.                                                                                                                                                 |
| `modules/local/picard/validatesamfile` | Still the nf-core template (`// TODO nf-core` comments). Gives 1 input; the process takes 4 (`[meta, bam, bai]`, `[meta2, fasta]`, `[meta3, fai]`, `[meta4, dict]`).                                                                                                                              |
| `modules/local/samtools/samples`       | Same as above: template test giving 1 input; the process takes 4.                                                                                                                                                                                                                                 |
| `modules/local/samtools/reheader`      | Input tuple is `[meta, bam]`; the process expects `[meta, input, header]`, so it fails with `Path value cannot be null`. Both the real test and the stub test fail.                                                                                                                               |
| `modules/local/seqfu/check`            | `tests/nextflow.config` sets `ext.args = params.module_args` inside a `withName:` block, which current Nextflow rejects (`Unknown config attribute process.withName:SEQFU_CHECK.params.module_args`). The `test_seqfu_fail - Safe exit` test also fails with a `NullPointerException` on `get()`. |
| `subworkflows/local/bam_id_repair`     | Gives no inputs; the subworkflow now takes 2 input channels.                                                                                                                                                                                                                                      |
| `subworkflows/local/vcf_id_repair`     | Input setup no longer matches the subworkflow (`Missing process or function map(...)`).                                                                                                                                                                                                           |

**To fix:**

- Update each test to the module's current `input:` block, using real test data of the right type (e.g. a VCF from nf-core test-datasets for the VCF tools, and meta that carries the IDs the header parsers need).
- Move `module_args` in the SEQFU test config to a top-level `params {}` block (or set `ext.args` directly).
- Regenerate the snapshots (`--updateSnapshot`). The failing run created new `.snap` entries for some of these tests; review them rather than trusting them.
- Then decide whether `run-test-suite.sh` step 5 should keep running the whole suite or use `--changed-since main` to match CI.

## 2026-11-26 – `-stub` runs crash on FASTQ inputs: `RENAME_FASTQ` has no stub

**Status:** Confirmed, not fixed (found while working on BIOINFO-252). To address in a separate ticket.

**Where:** `modules/local/rename_fastq/main.nf`, the only local module without a `stub:` block.

**What:** Any `-stub` run whose samplesheet contains FASTQ rows fails at `RENAME_FASTQ` with:

```
Error executing process > 'FERLAB_VALIDATION:SEQ_DATA_VALIDATION:RENAME_FASTQ (1)'
Caused by:
  Cannot invoke method clone() on null object
```

Nextflow cannot resolve a stub for the process (`TaskRun.resolveStub`). Reproduced with `NXF_VER=24.10.2 nextflow run . -profile test -stub` on the unmodified `data-test/testSamplesheet.csv`, which has one FASTQ pair (P002/S002). Samplesheets without FASTQ rows are not affected. Not checked on other Nextflow versions.

**Possible fix:** add a stub that mirrors the script's renaming, e.g. loop over `fastq_files` and `touch` the renamed file names (`${meta.sample}` substituted for `${meta.old_id}`, or prefixed when the old ID is absent), so the `*fastq*` output glob matches.
