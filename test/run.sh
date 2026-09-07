#!/usr/bin/env bash
# Static acceptance test for oxo-flow-mag port.
# Usage: ./test/run.sh            (uses ./main.oxoflow)
#
# NOTE: this is a static acceptance test (validate + lint + dry-run + debug),
# NOT an end-to-end run. An `oxo-flow run` would need the ~100 GB GTDB-Tk
# reference database and per-tool conda environments, which is impractical
# for CI; the pipeline has not been executed end-to-end (see README "Test").
set -euo pipefail
cd "$(dirname "$0")/.."
OXO=${OXO:-oxo-flow}

echo "==> validate"
"$OXO" validate main.oxoflow

echo "==> lint (warnings are acceptable, errors are not)"
"$OXO" lint main.oxoflow

echo "==> dry-run with default config"
# oxo-flow v0.11.0 prints the plan to stderr; capture both streams
"$OXO" dry-run main.oxoflow --samples first:1 > /tmp/oxo-dryrun-$$.txt 2>&1
grep -q "would execute" /tmp/oxo-dryrun-$$.txt

echo "==> debug: expanded commands contain no literal {wildcards}"
"$OXO" debug main.oxoflow 2>&1 | grep -q '{sample}' && { echo "unexpanded wildcards in debug output"; exit 1; } || true

echo "==> BigMAG branch: dry-run with generate_bigmag_file + run_gunc + run_checkm2"
# Upstream PREPARE_BIGMAG_SUMMARY (mag.nf:574-579) is gated on
# params.generate_bigmag_file and consumes BIN_SUMMARY.out.summary +
# BIN_QC.out.gunc_summary. Its setup validation (main.nf:418-420) errors
# unless --run_checkm2 and --run_gunc are set and BINQC/GTDB-Tk/QUAST/BUSCO
# are not skipped. The port keeps BUSCO/QUAST/BINQC always on and GTDB-Tk
# gated on run_gtdbtk (default true), so the flip enables the two gated
# inputs; run_checkm is not required by upstream either.
sed -e 's/^generate_bigmag_file = false$/generate_bigmag_file = true/' \
    -e 's/^run_gunc = false$/run_gunc = true/' \
    -e 's/^run_checkm2 = false$/run_checkm2 = true/' \
    main.oxoflow > .bigmag-test-tmp.oxoflow
grep -q '^generate_bigmag_file = true$' .bigmag-test-tmp.oxoflow
grep -q '^run_gunc = true$' .bigmag-test-tmp.oxoflow
grep -q '^run_checkm2 = true$' .bigmag-test-tmp.oxoflow
trap 'rm -f .bigmag-test-tmp.oxoflow' EXIT
"$OXO" dry-run .bigmag-test-tmp.oxoflow --samples first:1 > /tmp/oxo-dryrun-bigmag-$$.txt 2>&1
# Plan lines are plain rule names (no module prefix in this port)
grep -qE "^  [0-9]+\. bigmag_summary[^ ]*  \[run" /tmp/oxo-dryrun-bigmag-$$.txt \
    || { echo "BigMAG branch: bigmag_summary not scheduled"; exit 1; }
if grep -qE "^  [0-9]+\. bigmag_summary[^ ]*  \[run" /tmp/oxo-dryrun-$$.txt; then
    echo "BigMAG branch: bigmag_summary scheduled with default config"; exit 1
fi
rm -f .bigmag-test-tmp.oxoflow
trap - EXIT
echo "  bigmag_summary on when generate_bigmag_file is set; off by default"

echo "PASS (static acceptance + BigMAG branch flip)"