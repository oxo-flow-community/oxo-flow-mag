#!/usr/bin/env python3
"""Replicate the nf-core/mag 5.5.0 Groovy GTDB-Tk QC filter for one
(assembler, binner, sample) bin group.

Upstream (subworkflows/local/gtdbtk/main.nf) reads the per-group QC summaries
(qc_columns: busco -> Input_file/Complete/Duplicated, checkm -> Bin
Id/Completeness/Contamination), drops negative readings, drops bins without
any metric, and splits the rest: a bin passes if any single reading clears
both thresholds (gtdbtk_min_completeness, gtdbtk_max_contamination).

Semantics ported exactly:
  - negative completeness or contamination -> the whole reading is dropped
  - bins with no reading at all are dropped entirely (neither passed nor
    discarded; they never reach GTDB-Tk)
  - otherwise: pass iff any reading has completeness >= min AND
    contamination <= max; the rest are "discarded"
  - busco bin names in the batch summary are the decompressed file names
    (the nf-core busco module gunzips each input), i.e. bin name minus '.gz'
  - CheckM (and CheckM2) strip the extension from the bin name, so the
    upstream filter appends '.fa' to the checkm 'Bin Id' column before
    matching the bin files

Outputs: basenames WITH '.gz' (the real bin file names), one per line.
"""
import argparse
import glob
import os


def read_busco(path, metrics):
    with open(path) as fh:
        header = fh.readline().rstrip("\n").split("\t")
        cols = {name: i for i, name in enumerate(header)}
        for line in fh:
            row = line.rstrip("\n").split("\t")
            if len(row) < len(header):
                continue
            bin_name = row[cols["Input_file"]].removesuffix(".gz")
            try:
                completeness = float(row[cols["Complete"]])
                contamination = float(row[cols["Duplicated"]])
            except ValueError:
                continue
            # a negative value means the tool could not assess the bin: drop the reading
            if completeness < 0 or contamination < 0:
                continue
            metrics.setdefault(bin_name, []).append([completeness, contamination])


def read_checkm(path, metrics):
    # the checkm qa output ({prefix}_qa.txt) is a --tab_table with a header;
    # absent file means the branch did not run (run_checkm=false): no-op
    if not path or not os.path.exists(path):
        return
    with open(path) as fh:
        header = fh.readline().rstrip("\n").split("\t")
        cols = {name: i for i, name in enumerate(header)}
        for line in fh:
            row = line.rstrip("\n").split("\t")
            if len(row) < len(header):
                continue
            # checkm strips the extension from the bin name (upstream appends '.fa')
            bin_name = row[cols["Bin Id"]] + ".fa"
            try:
                completeness = float(row[cols["Completeness"]])
                contamination = float(row[cols["Contamination"]])
            except ValueError:
                continue
            if completeness < 0 or contamination < 0:
                continue
            metrics.setdefault(bin_name, []).append([completeness, contamination])


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--batch-summary", required=True,
                    help="BUSCO batch_summary.txt of the group")
    ap.add_argument("--checkm-qa-file", default=None,
                    help="optional CheckM qa output ({prefix}_qa.txt) of the group")
    ap.add_argument("--bins-dir", required=True,
                    help="directory containing the bin fasta files")
    ap.add_argument("--bins-glob", required=True,
                    help="glob pattern of the group's bins, relative to --bins-dir")
    ap.add_argument("--min-completeness", type=float, required=True)
    ap.add_argument("--max-contamination", type=float, required=True)
    ap.add_argument("--out-passed", required=True)
    ap.add_argument("--out-discarded", required=True)
    args = ap.parse_args()

    # bin name (basename minus .gz) -> [ [completeness, contamination], ... ]
    # one reading per QC tool (BUSCO always, CheckM when run_checkm=true)
    metrics = {}
    read_busco(args.batch_summary, metrics)
    read_checkm(args.checkm_qa_file, metrics)

    # the group's bin fasta files (python glob: zero matches -> empty lists,
    # mirroring the upstream empty-group behaviour)
    bins = sorted(glob.glob(os.path.join(args.bins_dir, args.bins_glob)))

    passed = []
    discarded = []
    for f in bins:
        base = os.path.basename(f)
        readings = metrics.get(base.removesuffix(".gz"))
        if readings is None:
            continue  # no QC metric for this bin: dropped entirely
        if any(c >= args.min_completeness and t <= args.max_contamination
               for c, t in readings):
            passed.append(base)
        else:
            discarded.append(base)

    with open(args.out_passed, "w") as fh:
        fh.write("\n".join(passed) + ("\n" if passed else ""))
    with open(args.out_discarded, "w") as fh:
        fh.write("\n".join(discarded) + ("\n" if discarded else ""))


if __name__ == "__main__":
    main()
