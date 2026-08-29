#!/usr/bin/env bash
# Build the reads-sheet test fixtures: 1 PE + 1 SE + 1 interleaved sample,
# all derived from the repo's tiny raw fixtures (absolute paths in the sheet).
set -euo pipefail
cd "$(dirname "$0")/.."
RAW="$(pwd)/test/fixtures/raw"
mkdir -p test/fixtures
# interleaved = R1+R2 gz streams concatenated (fastp --interleaved_in reads
# the pairs alternately from one stream)
cat "$RAW/S1_R1.fastq.gz" "$RAW/S1_R2.fastq.gz" > test/fixtures/interleaved_IL1.fastq.gz
printf 'sample\treads_1\treads_2\treads_layout\n' > test/fixtures/reads_sheet.tsv
printf 'S1\t%s/S1_R1.fastq.gz\t%s/S1_R2.fastq.gz\tpe\n' "$RAW" "$RAW" >> test/fixtures/reads_sheet.tsv
printf 'SE1\t%s/S1_R1.fastq.gz\t\tsingle\n' "$RAW" >> test/fixtures/reads_sheet.tsv
printf 'IL1\t%s/interleaved_IL1.fastq.gz\t\tinterleaved\n' "$(pwd)/test/fixtures" >> test/fixtures/reads_sheet.tsv
cat test/fixtures/reads_sheet.tsv
