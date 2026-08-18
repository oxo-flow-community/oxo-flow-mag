#!/usr/bin/env python3
"""Generate the synthetic metagenome fixtures for oxo-flow-mag.

The shipped fixtures (a few dozen reads) are below SPAdes' viable input:
with ~10 read pairs the assembler writes no scaffolds.fasta at all and the
rule silently exited 0 (live). This generator emits a small but REAL
metagenome — three 30 kb genomes with distinct GC content and 4-mer
profiles, sequenced as 150 bp paired-end reads at differential abundance
between the two samples — so assembly produces genuine contigs and the
binners have real composition + coverage signal.

Design:
- 3 species (G1: 35% GC, G2: 50% GC, G3: 65% GC), 30 kb circular each
- 150 bp PE reads, ~300 bp inserts, 0.5% sequencing error, Illumina-style
- S1 abundances: G1 30x, G2 20x, G3 10x; S2: G1 10x, G2 20x, G3 30x
  (~6000 pairs per sample, ~1 MB gzipped each)
- no contaminants beyond the three genomes, so phiX removal is a no-op
  (exercises the rule without eating reads)

Regenerate with:  python3 test/fixtures/generate_fixtures.py
"""
import gzip
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
READ_LEN = 150
INSERT = 300
ERROR_RATE = 0.005
SEED = 42

# species -> (GC target, abundance in S1, abundance in S2)
SPECIES = [
    ("G1", 0.35, 30, 10),
    ("G2", 0.50, 20, 20),
    ("G3", 0.65, 10, 30),
]
GENOME_LEN = 30000


def random_genome(rng, gc):
    """A 30 kb sequence with a target GC content and a di-nucleotide bias
    (bases tend to repeat their class), giving each genome a distinct
    tetranucleotide profile for the composition-based binners."""
    p = {"A": (1 - gc) / 2, "C": gc / 2, "G": gc / 2, "T": (1 - gc) / 2}
    seq = [rng.choices("ACGT", weights=[p[b] for b in "ACGT"], k=1)[0] for _ in range(GENOME_LEN)]
    for i in range(1, GENOME_LEN):
        if rng.random() < 0.35:
            prev = seq[i - 1]
            if prev in "AT":
                w = [0.4 * (1 - gc) * 2, gc / 2, gc / 2, 0.4 * (1 - gc) * 2]
            else:
                w = [(1 - gc) / 2, 0.4 * gc * 2, 0.4 * gc * 2, (1 - gc) / 2]
            seq[i] = rng.choices("ACGT", weights=w, k=1)[0]
    return "".join(seq)


def reverse_complement(seq):
    comp = str.maketrans("ACGT", "TGCA")
    return seq[::-1].translate(comp)


def qualities(length, rng):
    """Illumina-like Phred+33 string: high at the 5' end, declining
    towards the tail. Uniform quality chars make SPAdes' offset
    detection fail ('Failed to determine offset!' — live)."""
    qs = []
    for i in range(length):
        q = 38 - 15 * (i / length) + rng.gauss(0, 1.5)
        qs.append(chr(33 + int(max(2, min(40, round(q))))))
    return "".join(qs)


def make_reads(genome, n_pairs, rng):
    """150 bp PE reads from a circular genome at ~300 bp inserts."""
    out1, out2 = [], []
    for _ in range(n_pairs):
        start = rng.randrange(GENOME_LEN)
        insert = max(READ_LEN, rng.randint(INSERT - 100, INSERT + 100))
        end = start + insert
        read1 = (genome[start:end] if end <= GENOME_LEN
                 else genome[start:] + genome[: end - GENOME_LEN])
        read2 = reverse_complement(read1[insert - READ_LEN : insert])
        read1 = read1[:READ_LEN]
        # sequencing error
        read1 = "".join(
            c if rng.random() > ERROR_RATE else rng.choice([b for b in "ACGT" if b != c])
            for c in read1
        )
        read2 = "".join(
            c if rng.random() > ERROR_RATE else rng.choice([b for b in "ACGT" if b != c])
            for c in read2
        )
        out1.append(f"@{_}/1\n{read1}\n+\n{qualities(READ_LEN, rng)}")
        out2.append(f"@{_}/2\n{read2}\n+\n{qualities(READ_LEN, rng)}")
    return out1, out2


def write_sample(sample, abundances, rng):
    r1, r2 = [], []
    pair_id = 0
    for name, gc, _, _ in SPECIES:
        genome = random_genome(rng, gc)
        cov = abundances[name]
        n_pairs = GENOME_LEN * cov // (2 * READ_LEN)  # coverage formula, PE
        a, b = make_reads(genome, n_pairs, rng)
        for read1, read2 in zip(a, b):
            header = f"@{sample}_{name}_{pair_id}"
            r1.append(header + read1[read1.index("/"):])
            r2.append(header + read2[read2.index("/"):])
            pair_id += 1
    # interleave randomly so assemblers see a mixed community
    order = list(range(pair_id))
    rng.shuffle(order)
    r1 = [r1[i] for i in order]
    r2 = [r2[i] for i in order]
    for suffix, reads in (("R1", r1), ("R2", r2)):
        with gzip.open(os.path.join(RAW, f"{sample}_{suffix}.fastq.gz"), "wt") as fh:
            fh.write("\n".join(reads) + "\n")
    return pair_id


def main():
    os.makedirs(RAW, exist_ok=True)
    rng = random.Random(SEED)
    for sample in ("S1", "S2"):
        ab = {name: (a if sample == "S1" else b) for name, _, a, b in SPECIES}
        n = write_sample(sample, ab, rng)
        print(f"{sample}: {n} pairs")
    print("mag fixtures regenerated: 3x30kb community, 150bp PE, differential abundance")


if __name__ == "__main__":
    main()
