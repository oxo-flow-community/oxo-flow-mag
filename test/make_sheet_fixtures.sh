#!/usr/bin/env bash
# Build the reads-sheet test fixtures: 1 PE + 1 SE + 1 interleaved sample +
# a two-lane merged base (S1_lane1/S1_lane2, base S1 — see main.oxoflow
# multi-lane merging), all derived from the repo's tiny raw fixtures
# (absolute paths in the sheet).
set -euo pipefail
cd "$(dirname "$0")/.."
RAW="$(pwd)/test/fixtures/raw"
FIX="$(pwd)/test/fixtures"
mkdir -p "$FIX"
# interleaved = R1+R2 gz streams concatenated (fastp --interleaved_in reads
# the pairs alternately from one stream)
cat "$RAW/S1_R1.fastq.gz" "$RAW/S1_R2.fastq.gz" > "$FIX/interleaved_IL1.fastq.gz"
# lane split: each lane gz holds every 2nd 4-line record (gzip blocks stay
# independently decompressible, so a byte-slice concat like the interleaved
# fixture above would NOT interleave cleanly; awk keeps record integrity)
for mate in 1 2; do
    for lane in 1 2; do
        src="$RAW/S1_R${mate}.fastq.gz"
        dst="$FIX/S1_lane${lane}_R${mate}.fastq.gz"
        if [ "$lane" = 1 ]; then
            gzip -cd "$src" | awk 'NR%8<4' | gzip > "$dst"
        else
            gzip -cd "$src" | awk 'NR%8>=4' | gzip > "$dst"
        fi
    done
done
printf 'sample\treads_1\treads_2\treads_layout\n' > "$FIX/reads_sheet.tsv"
printf 'S2\t%s/S2_R1.fastq.gz\t%s/S2_R2.fastq.gz\tpe\n' "$RAW" "$RAW" >> "$FIX/reads_sheet.tsv"
printf 'SE1\t%s/S1_R1.fastq.gz\t\tsingle\n' "$RAW" >> "$FIX/reads_sheet.tsv"
printf 'IL1\t%s/interleaved_IL1.fastq.gz\t\tinterleaved\n' "$FIX" >> "$FIX/reads_sheet.tsv"
printf 'S1_lane1\t%s/S1_lane1_R1.fastq.gz\t%s/S1_lane1_R2.fastq.gz\tpe\n' "$FIX" "$FIX" >> "$FIX/reads_sheet.tsv"
printf 'S1_lane2\t%s/S1_lane2_R1.fastq.gz\t%s/S1_lane2_R2.fastq.gz\tpe\n' "$FIX" "$FIX" >> "$FIX/reads_sheet.tsv"
cat "$FIX/reads_sheet.tsv"
