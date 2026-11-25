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
