#!/usr/bin/env bash
# Manual smoke-test runs: real `nextflow run` executions against the full
# S3 test dataset via Docker. Unlike scripts/run-test-suite.sh, these don't
# assert anything themselves beyond Nextflow's own exit code -- they're
# meant to be eyeballed afterward (renamed files, manifests, logs,
# pipeline_info/, etc.), which is why each one gets its own persistent,
# inspectable --outdir rather than nf-test's ephemeral per-test directories.
#
# Requires:
#   - Docker running
#   - data-test/ synced locally, e.g.:
#       aws s3 cp s3://ferlab-public-dataset/nextflow/seq-data-validation/V1/data-test data-test --recursive
#
# Existing output directories are left alone (not wiped) so you can diff
# against a previous run; use `nextflow clean -f` or remove them yourself
# if you want a clean slate.
#
# Usage: scripts/run-smoke-tests.sh

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

export NXF_FILE_ROOT="$PWD"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found on PATH." >&2; exit 1; }
}
require nextflow
require docker

if [ ! -d data-test ]; then
    echo "ERROR: data-test/ not found. Sync it first (same dataset as .github/workflows/nf-test.yml):" >&2
    echo "  aws s3 cp s3://ferlab-public-dataset/nextflow/seq-data-validation/V1/data-test data-test --recursive" >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker doesn't appear to be running." >&2
    exit 1
fi

step() { echo; echo "==> $1"; }

step "[1/3] debug + test profile -> ./results_debug"
nextflow run . -profile debug,test,docker --outdir ./results_debug

step "[2/3] test profile -> ./results_test"
nextflow run . -profile test,docker --outdir ./results_test

# The test profile enables --replace_sample_id; this covers the other main
# code path (validation + manifest only, files left untouched).
step "[3/3] validation only (--replace_sample_id false) -> ./results_no_replace"
nextflow run . -profile test,docker \
    --replace_sample_id false \
    --outdir ./results_no_replace

echo
echo "Smoke runs complete. Inspect ./results_debug/, ./results_test/, ./results_no_replace/ ."
