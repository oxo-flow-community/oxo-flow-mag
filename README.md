# oxo-flow-mag

Metagenome assembly and binning — an [oxo-flow](https://github.com/Traitome/oxo-flow)
port of [nf-core/mag](https://github.com/nf-core/mag) **5.5.0**
(commit `56abab5b023ce953c9c43fe21090d156ad0e18af`).

## Overview

The default short-read path of nf-core/mag, ported faithfully to a single
oxo-flow workflow with 134 rules:

```
FastQC -> fastp -> phiX removal -> FastQC
  -> SPAdes + MEGAHIT assembly
  -> QUAST + Prodigal per assembly
  -> bowtie2 index + per-sample alignments (group mode)
  -> contig depths (JGI summary)
  -> MetaBAT2 / MaxBin2 / CONCOCT / COMEBin / MetaBinner / SemiBin2
  -> seqkit stats + split_fasta (unbinned contig chunks)
  -> BUSCO bin QC (bins + chunks, --auto-lineage)
  -> per-group QUAST + MAG depths summaries (qsv cat rowskey)
  -> ALE assembly evaluation
  -> GTDB-Tk classification of QC-passing bins (BUSCO filter)
  -> gtdbtk_summary + bin_summary + PROKKA annotation
  -> MultiQC report
```

Tool versions and resource requests (cpu/memory/time per process label)
match the upstream module environments and `conf/base.config`. The port
deviates in the places listed in the fidelity table below (upstream
behaviors that had to be replicated inside oxo-flow's shared-working-
directory model, and one deliberate divergence: the GTDB-Tk database is
not downloaded mid-run). See `envs/*.yaml` for the pinned environments.

## Usage

```bash
oxo-flow run main.oxoflow
```

Samples are discovered from `config.input_dir` (default
`test/fixtures/raw`) as `{sample}_R1.fastq.gz` / `{sample}_R2.fastq.gz`.
The cohort (default `S1 S2`) controls which assemblies each sample is
aligned against, exactly like the upstream `binning_map_mode = 'group'`.

### GTDB-Tk database

Upstream downloads the GTDB reference data from a URL by default; oxo-flow
cannot download mid-run, so `config.gtdb_db` must point to a local file or
directory. Either download the tarball

```bash
curl -fL -o gtdbtk_data.tar.gz \
  "https://data.gtdb.ecogenomic.org/releases/latest/auxillary_files/gtdbtk_data.tar.gz"
```

and set `gtdb_db = "gtdbtk_data.tar.gz"`, or unpack it and pass the
directory. Both forms are accepted by the `gtdbtk_db_preparation` rule
(tar.gz and directory input).

## Configuration

All upstream `params` with their default values are exposed in the
`[config]` section of [main.oxoflow](main.oxoflow): QC thresholds
(`reads_minlength`, `fastp_qualified_quality`, ...), binning parameters
(`bin_min_size`, `min_length_unbinned_contigs`, `max_unbinned_contigs`,
CONCOCT chunk size/overlap, MetaBinner scale, SemiBin2 RNG seed/environment,
MetaBAT2 RNG seed), GTDB-Tk thresholds (`gtdbtk_min_completeness`,
`gtdbtk_max_contamination`, `gtdbtk_min_perc_aa`, `gtdbtk_min_af`,
`gtdbtk_pplacer_cpus`) and the cohort. Unsupported upstream parameters are
omitted (see the fidelity table).

## Outputs

`results/` mirrors the upstream `outdir` layout:

- `QC_shortreads/` — FastQC html, fastp json/html, bowtie2 phiX logs
- `Assembly/{SPAdes,MEGAHIT}/` — assembly fasta (gz), logs, `QC/{sample}/`
  with the QUAST report files and `ALE/`
- `Annotation/Prodigal/{SPAdes,MEGAHIT}/{sample}/` — fna/gff/faa/all.txt (gz)
- `Annotation/Prokka/{SPAdes,MEGAHIT}/` — per-bin PROKKA output
- `GenomeBinning/{binner}/bins/` and `.../unbinned/` — bins and contig
  chunks; `MetaBAT2/discarded/` and `MetaBinner/discarded/` — contigs
  rejected by the binners (as upstream); `MetaBinner/unbinned/` — the
  unbinned contigs; `CONCOCT/stats/` — clustering tables; `QC/BUSCO/.../` —
  BUSCO summaries; `QC/*.tsv` — concatenated summaries; `depths/bins/` —
  per-bin depths; `bin_summary.tsv`
- `Taxonomy/GTDB-Tk/{assembler}/{binner}/{sample}/` — GTDB-Tk output trees,
  `gtdbtk_summary.tsv`
- `multiqc/multiqc_report.html`

## Fidelity table

| Upstream | Port | Notes |
|----------|------|-------|
| Process-per-(assembler, binner) with `meta` tuples | One rule per (assembler, binner, ...) combination, names hard-coded | oxo-flow has no assembler/binner wildcard; `04_binning` has 48 rules, `05_binqc` 41, `06_taxonomy` 28 |
| Nextflow task workdir per process | Shared workflow dir + per-rule `.tmp/` scratch dirs | Tools that write generic-named files (spades, megahit, busco, quast, prokka, gtdbtk) run inside a scratch subdir and move outputs out |
| bash task scripts | `sh -c` executor | Process substitution (`2> >(tee ...)` in fastp) replaced with a plain redirect; brace expansion (`short_summary.*.{txt,json}`) split into two `mv` commands |
| Two BUSCO/GTDB-Tk/QUAST_BINS/MAG_DEPTHS runs per group (bins + chunks) | One rule per group that runs the tool twice in separate scratch subdirs | The two upstream runs share output names (`S1-auto-busco.*`); they are kept apart by the publish dirs `...-unclassified-unrefined-{sample}/` and `...-unclassified-unrefined_unbinned-{sample}/` |
| GTDB-Tk QC filter (Groovy) | `scripts/filter_bins_by_qc.py` | Same semantics: negative readings dropped, bins without metrics dropped, pass iff any reading clears both thresholds; BUSCO `Duplicated` is the contamination column |
| `gtdbtk_single_job` option | Not ported | Off by default upstream |
| `gtdbtk_use_full_tree` / `gtdbtk_place_species` | Config keys not exposed | Off by default upstream |
| Empty bin groups crash upstream (BUSCO on no input) | Empty groups produce empty/touched outputs and skip downstream classification | The pipeline never fails on empty groups |
| Versions.yml / pipeline boilerplate (summary, methods_description) | Not ported | Not analysis output |
| `*-busco.batch_summary.failed.txt` | Not produced | Only exists upstream when a BUSCO run failed |
| `results/GenomeBinning/QC/BUSCO/` flat short_summaries | Published into the same per-group dir as upstream | Same publish pattern `*{.txt,.json,.log}` |
| Conda environments | `envs/*.yaml` with the same pins | `tar` added to `gunzip`/`gtdbtk_db_preparation` because there is no container layer; `split_fasta` and `mag_depths` pin `conda-forge::pandas=1.1.5` exactly like upstream (the other pins use the `bioconda::` channel prefix instead of `conda-forge::` — same package, same version) |
| QUAST_BINS / BUSCO / GTDB-Tk file names | `{assembler}-{binner}-unclassified-unrefined-{sample}[-unbinned]-...` in summary names, QC dirs and input globs | Matches upstream meta naming (`domain=unclassified`, `refinement=unrefined`/`unrefined_unbinned`); the port previously omitted `{sample}` from QUAST summary names and used `-unclassified-unrefined-` in bin input globs, where the files are actually named `{assembler}-{binner}-{sample}*` — the globs matched nothing (fixed) |
| METABAT2 `-m` clamp | `<1500` is clamped to `1500` in the rule shell | Upstream clamps in `conf/modules.config` (`ext.args`); port replicates it with a shell guard |
| METABAT2 / METABINNER_BINS discarded bins | tooShort/lowDepth moved to `GenomeBinning/{binner}/discarded/`; METABINNER unbinned also copied to `GenomeBinning/MetaBinner/unbinned/` | Matches the upstream `publishDir` patterns; the lowDepth move is guarded because `create_metabinner_bins.py` never emits that file |
| CONCOCT stats | clustering/merged CSV and coverage TSV copied to `GenomeBinning/CONCOCT/stats/` | Matches the upstream `*.{txt,csv,tsv}` publish pattern |
| COMEBin | no `-s large` argument | Upstream `COMEBIN_RUNCOMEBIN` passes no `ext.args` (the `-s` scale flag belongs to MetaBinner, which does pass it) |
| SemiBin2 `--environment` | passed only for single-sample cohorts | Matches upstream `meta.sample_count == 1` in `ext.args2` |
| METABINNER coverage profile | contig length filter uses `{config.min_contig_size}` (was hardcoded 1500) | Upstream passes `val_min_contig_size` to the awk filter |
| SPAdes (METASPADES) resources | 10 cpu / 72 GB / 24 h (was 12 cpu / 16 h) | Matches upstream `base.config` (`cpus = 10 * attempt`, `time = 24.h * attempt`); the `--memory 72` flag matches `memory = 72.GB` |
| MultiQC | report published to `multiqc/` (lowercase) with `--force` | Matches upstream publishDir and the nf-core multiqc module script |
| Convert-depths / split_fasta scratch | per-sample scratch dirs and guarded sample-scoped globs | oxo-flow executes rules in one shared working directory (upstream gives every task its own); the generic `mv *.abund` / `mv *.pooled.fa.gz *.remaining.fa.gz` would otherwise race or fail when a sample produces no such files |

### Not ported (off by default upstream)

Long-read assembly and binning, DAS Tool refinement, kaiju and diamond
taxonomic profiling, CheckM/CheckM2/GUNC QC, tiara domain classification,
host removal, ancient DNA, CAT/BAT, pydamage, hybrid assembly, and the
benchmarking modes.

## Test

```bash
./test/run.sh    # static acceptance: validate + lint + dry-run + debug
```

The acceptance test needs only `oxo-flow` (v0.11.0+) on `PATH` (override
with `OXO=/path/to/oxo-flow`); no conda environments or databases are
required for validation.

**Status: static acceptance only.** The pipeline has not been executed
end-to-end: a real run requires the GTDB-Tk reference database (~100 GB
download) and per-tool conda environments, which is impractical for CI.
The workflow graph, rule commands, config expansion and DAG wiring are
verified by `validate` + `lint` + `dry-run` + `debug`; runtime behavior
of the underlying tools is unchanged from upstream nf-core/mag.
