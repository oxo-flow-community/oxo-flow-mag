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

echo "PASS (static acceptance: validate + lint + dry-run + debug)"