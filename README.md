# oxo-flow-mag — Metagenome assembly, binning and taxonomic classification

[![CI](https://github.com/oxo-flow-community/oxo-flow-mag/actions/workflows/ci.yml/badge.svg)](https://github.com/oxo-flow-community/oxo-flow-mag/actions/workflows/ci.yml)

> ★ Verified · ⇄ Official port of [`nf-core/mag`](https://github.com/nf-core/mag) @ `5.5.0` — same tools, same versions, same commands. Part of the [oxo-flow-community catalog](https://oxo-flow-community.github.io/).

Run this workflow and paired-end metagenomic reads become quality-checked, assembled, binned and taxonomically classified draft genomes. Reads are trimmed and cleared of phiX contamination (FastQC + fastp + bowtie2), assembled with both SPAdes and MEGAHIT, and assessed with QUAST and Prodigal. The assemblies are then binned with six complementary binners (MetaBAT2, MaxBin2, CONCOCT, COMEBin, MetaBinner, SemiBin2), the bins QC'd with BUSCO and classified with GTDB-Tk, annotated with PROKKA, and everything is summarized into a single MultiQC report. The optional upstream branches — host read removal, read normalization (bbnorm), adapterremoval/trimmomatic clipping, DAS Tool refinement, CheckM bin QC and Tiara domain classification — are ported as when-gated rules, all off by default (see [Gated branches](#gated-branches)):

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

Optional branches, each gated by one config key (off by default):
  (optional) adapterremoval / trimmomatic clipping        config.clip_tool
  (optional) host read removal (bowtie2)                  config.host_fasta
  (optional) read normalization                           config.bbnorm
  (optional) DAS Tool bin refinement                      config.refine_bins_dastool
  (optional) CheckM bin QC (feeds the GTDB-Tk filter)     config.run_checkm
  (optional) Tiara domain classification                  config.bin_domain_classification
```

Tool versions and resource requests (cpu/memory/time per process label) match the upstream module environments and `conf/base.config`. The workflow deviates only in the places listed in the fidelity table below, and in one deliberate divergence: the GTDB-Tk database is not downloaded mid-run (see [Requirements](#3-requirements) and [Usage](#usage)). See `envs/*.yaml` for the pinned environments.

## Installation

### 1. Install oxo-flow

This workflow requires **oxo-flow >= 0.12.0**. The release binary is recommended:

```bash
curl -fL -o oxo-flow.tar.gz https://github.com/Traitome/oxo-flow/releases/latest/download/oxo-flow-latest-x86_64-unknown-linux-gnu.tar.gz
tar xzf oxo-flow.tar.gz && sudo mv oxo-flow /usr/local/bin/
```

Alternatively, install via conda:

```bash
conda install -c bioconda oxo-flow-cli
```

Note: the conda package may lag behind releases; binaries for other platforms are available on the [releases page](https://github.com/Traitome/oxo-flow/releases).

### 2. Get this workflow

```bash
git clone https://github.com/oxo-flow-community/oxo-flow-mag.git
cd oxo-flow-mag
```

### 3. Requirements

Derived from the workflow's own inputs and `[rules.resources]`:

- **Reference data you must provide:**
  - Your paired-end reads as `{sample}_R1.fastq.gz` / `{sample}_R2.fastq.gz` per sample in `config.input_dir` (default `test/fixtures/raw`, which ships tiny test fixtures — point this at your data). Single-end and multi-library lanes are not ported.
  - A GTDB-Tk reference database for the classification step: oxo-flow cannot download it mid-run, so you must download the release tarball (`gtdbtk_data.tar.gz`, ~100 GB) or unpack it to a directory and set `config.gtdb_db` (see [Usage](#usage)).
  - The phiX reference is already bundled in the repo (`assets/data/GCA_002596845.1_ASM259684v1_genomic.fna.gz`, the upstream default) — no download needed.
- **Compute:** per-rule requests go up to 12 CPUs and 140 GB RAM — SPAdes requests 10 CPUs / 72 GB / 24 h, GTDB-Tk classifywf 2 CPUs / 140 GB / 12 h (defaults are 1 thread / 6 GB). A large-memory machine or cluster is expected for real datasets; the resource pool queues rules so the sum of parallel rules can exceed your machine.
- **Tools:** delivered as **conda environments with pinned versions** — one `envs/*.yaml` per tool, pinning the exact package versions of the upstream nf-core module environments. You need conda (or mamba) installed; there is no container layer, so Docker/Singularity are not used.
- **CheckM data (first metabinner env creation):** the `metabinner` environment's checkm-genome package downloads the CheckM reference data (~1.1 GB, `data.ace.uq.edu.au`, sha256 `971ec469…`) when the env is first created — upstream bakes this into its containers at build time. If that host is slow for you, download `checkm_data_2015_01_16.tar.gz` yourself and re-create the env with `CHECKM_DATA_PATH=/path/to/checkm_data_2015_01_16.tar.gz` exported — checkm-genome's installer then copies the local file instead of downloading. The `--run_checkm` branch uses the same reference data via `envs/checkm.yaml` (same checkm-genome pin as the upstream module); point `config.checkm_db` at the local unpacked `checkm_data_2015_01_16` directory to skip the first-use download.
- **Optional references (only when the matching branch is enabled):** a host genome FASTA for `config.host_fasta` (host read removal); a prebuilt bowtie2 index for `config.host_fasta_bowtie2index` (skips the build rule); Tiara downloads its model on first use of the `--bin_domain_classification` branch.
- **ALE (one-time source build):** the upstream pin (`ale=20180904` from bioconda) is uninstallable — its pymix chain needs matplotlib <1.5, which no channel carries. The rules only call ALE's C binaries, so `envs/ale.yaml` ships the build toolchain and `scripts/build_ale.sh` compiles the pinned upstream source tag into the env (idempotent): `bash scripts/build_ale.sh` after the env is created.

## Usage

```bash
oxo-flow run main.oxoflow
```

Samples are discovered from `config.input_dir` (default `test/fixtures/raw`) as `{sample}_R1.fastq.gz` / `{sample}_R2.fastq.gz`. The cohort (default `S1 S2`) controls which assemblies each sample is aligned against, exactly like the upstream `binning_map_mode = 'group'`.

### GTDB-Tk database

Upstream downloads the GTDB reference data from a URL by default; oxo-flow cannot download mid-run, so `config.gtdb_db` must point to a local file or directory. Either download the tarball

```bash
curl -fL -o gtdbtk_data.tar.gz \
  "https://data.gtdb.ecogenomic.org/releases/latest/auxillary_files/gtdbtk_data.tar.gz"
```

and set `gtdb_db = "gtdbtk_data.tar.gz"`, or unpack it and pass the directory. Both forms are accepted by the `gtdbtk_db_preparation` rule (tar.gz and directory input).

### Configuration

All upstream `params` with their default values are exposed in the `[config]` section of [main.oxoflow](main.oxoflow): QC thresholds (`reads_minlength`, `fastp_qualified_quality`, ...), binning parameters (`bin_min_size`, `min_length_unbinned_contigs`, `max_unbinned_contigs`, CONCOCT chunk size/overlap, MetaBinner scale, SemiBin2 RNG seed/environment, MetaBAT2 RNG seed), GTDB-Tk thresholds (`gtdbtk_min_completeness`, `gtdbtk_max_contamination`, `gtdbtk_min_perc_aa`, `gtdbtk_min_af`, `gtdbtk_pplacer_cpus`) and the cohort. Unsupported upstream parameters are omitted (see the fidelity table).

Override any config value on the command line with `KEY=VALUE` arguments (`oxo-flow run main.oxoflow clip_tool=trimmomatic`). The optional branches are switched on the same way: `host_fasta=path/to/host.fna`, `bbnorm=true`, `refine_bins_dastool=true`, `run_checkm=true`, `bin_domain_classification=true`, `clip_tool=adapterremoval|trimmomatic`.

### Outputs

`results/` mirrors the upstream `outdir` layout:

- `QC_shortreads/` — FastQC html, fastp json/html, bowtie2 phiX logs; adapterremoval/trimmomatic logs and host removal logs under `bbmap/` when those branches are on
- `Assembly/{SPAdes,MEGAHIT}/` — assembly fasta (gz), logs, `QC/{sample}/` with the QUAST report files and `ALE/`
- `Annotation/Prodigal/{SPAdes,MEGAHIT}/{sample}/` — fna/gff/faa/all.txt (gz)
- `Annotation/Prokka/{SPAdes,MEGAHIT}/` — per-bin PROKKA output
- `GenomeBinning/{binner}/bins/` and `.../unbinned/` — bins and contig chunks; `MetaBAT2/discarded/` and `MetaBinner/discarded/` — contigs rejected by the binners (as upstream); `MetaBinner/unbinned/` — the unbinned contigs; `CONCOCT/stats/` — clustering tables; `QC/BUSCO/.../` — BUSCO summaries; `QC/*.tsv` — concatenated summaries; `QC/CheckM/` — CheckM lineage QC (with `--run_checkm`); `DASTool/{bins,unbinned}/` — DAS Tool refined bins (with `--refine_bins_dastool`); `Tiara/` — per-group domain classification tables (with `--bin_domain_classification`); `depths/bins/` — per-bin depths; `bin_summary.tsv`
- `Taxonomy/GTDB-Tk/{assembler}/{binner}/{sample}/` — GTDB-Tk output trees, `gtdbtk_summary.tsv`
- `Taxonomy/Tiara/` — per-assembly Tiara probability tables (with `--bin_domain_classification`)
- `multiqc/multiqc_report.html`

## Source

- Upstream: [nf-core/mag](https://github.com/nf-core/mag) @ `5.5.0` (commit `56abab5b023ce953c9c43fe21090d156ad0e18af`)
- Upstream license: MIT (included verbatim in `LICENSE.upstream`)
- Created 2026-08-15; this workflow may lag behind upstream releases.
- Attribution and provenance details: see [NOTICE.md](NOTICE.md).

## Fidelity

| Upstream | Port | Notes |
|----------|------|-------|
| Process-per-(assembler, binner) with `meta` tuples | One rule per (assembler, binner, ...) combination, names hard-coded | oxo-flow has no assembler/binner wildcard; `04_binning` has 48 rules, `05_binqc` 66, `06_taxonomy` 28, `07_refinement` 28, `08_domain` 39 (231 rules total) |
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
| BINNING_REFINEMENT (DAS Tool) | `07_refinement.oxoflow`, 28 rules gated on `config.refine_bins_dastool` | RENAME_PREDASTOOL -> FASTATOCONTIG2BIN -> DASTOOL_DASTOOL -> RENAME_POSTDASTOOL mirror the upstream wiring; empty binner groups are dropped before DAS Tool exactly like upstream (`binners with no bins never reach DAS Tool`); the `_DASTool_bins`, log/summary/eval/seqlength aux files and `_DASToolUnbinned` gz are published to `GenomeBinning/DASTool/` |
| DAS Tool contig2bin join (upstream bash quirk) | `IFS=\t'` (ANSI-C) instead of upstream `IFS=$"\t"` | Verified empirically: `IFS=$"\t"` splits on the letter `t`, not tabs, so the upstream tiara_classify while-loop is broken for bin names containing `t` (e.g. MetaBAT2); the port uses the ANSI-C form |
| CHECKM_LINEAGEWF / CHECKM_QA (--run_checkm) | `05_binqc.oxoflow` + 25 rules, gated on `config.run_checkm` | `run_checkm()` shell function (gunzip-to-scratch with `-x fa`, `--pplacer_threads`, empty-group touched artifacts), then `checkm qa` with `-o 2 --tab_table`; both per-(assembler, binner) runs cover bins and unbinned chunks; outputs land in `GenomeBinning/QC/CheckM/` with the `-unclassified-unrefined[-_unbinned]` naming; a qsv rowskey concat produces `checkm_summary.tsv` |
| CheckM metrics into the GTDB-Tk filter | `filter_bins_by_qc.py --checkm-qa-file` on both gtdbtk rules; `bin_summary` passes `--checkm_summary` | Matches upstream: with `--run_checkm` the GTDB-Tk filter uses CheckM completeness/contamination instead of BUSCO; without it (the default) the BUSCO-only filter matches the upstream default config |
| TIARA_TIARA / TIARA_CLASSIFY (--bin_domain_classification) | `08_domain.oxoflow`, 39 rules gated on `config.bin_domain_classification` | `tiara --probabilities` per assembly, FASTATOCONTIG2BIN per (assembler, binner, bins/unbins) group, `domain_classification.R --join_prokaryotes` per group, one qsv-concatenated `tiara_summary.tsv`; unbins groups exist only for the three binners upstream splits (MetaBAT2, MaxBin2, MetaBinner); only the classification tables are published (as upstream) |

### Gated branches (all off by default, one config key each)

| Branch | Config key | Rules | Upstream process |
|--------|-----------|-------|------------------|
| AdapterRemoval clipping | `clip_tool = "adapterremoval"` | 1 | `ADAPTERREMOVAL` (nf-core/adapterremoval 2.3.2) |
| Trimmomatic clipping | `clip_tool = "trimmomatic"` | 1 | `TRIMMOMATIC` (nf-core/trimmomatic 0.39) |
| Host read removal | `host_fasta = "path/to/host.fna"` | 2 | `HOST_REMOVAL_BUILD`, `HOST_REMOVAL_ALIGN` (bowtie2; `host_fasta_bowtie2index` skips the build, `host_removal_verysensitive` toggles `--very-sensitive`) |
| Read normalization | `bbnorm = true` | 1 | `BBNORM` (bbmap 39.18, params `bbnorm_target`/`bbnorm_min`) |
| DAS Tool bin refinement | `refine_bins_dastool = true` | 28 | `BINNING_REFINEMENT` subworkflow (`refine_bins_dastool_threshold`) |
| CheckM bin QC | `run_checkm = true` | 25 | `CHECKM_LINEAGEWF` + `CHECKM_QA` (checkm-genome 1.2.5); feeds the GTDB-Tk filter (`checkm_db` optional local lineage DB) |
| Tiara domain classification | `bin_domain_classification = true` | 39 | `TIARA` subworkflow (tiara 1.0.3, `tiara_min_length`) |

Each gate activates exactly its own branch: with the default config the 260-rule plan is identical to the pre-branch port, and toggling one key adds only that branch's rules (verified by `dry-run` per key).

### Not ported (with reasons)

- **Long-read assembly and binning** (`--longreads`): the upstream longreads subworkflow doubles the whole binning graph (every assembler x binner x sample) and needs long-read input files the paired-end `{sample}_R1/_R2` input model does not provide.
- **Kaiju and diamond taxonomic profiling**: absent from upstream 5.5.0 entirely (removed upstream) — there is no module script to translate.
- **CheckM2 / GUNC QC** (`--run_checkm2`, `--run_gunc`): the CheckM2 (~8 GB) and GUNC (~21 GB) databases are remote downloads the engine cannot fetch mid-run; the ported CheckM branch needs only the CheckM reference data, which the checkm-genome package fetches once at conda env creation.
- **Single-end / interleaved input modes** (upstream `--input` samplesheet modes): the port's input model is paired-end `{sample}_R1.fastq.gz` / `{sample}_R2.fastq.gz` only.
- **Ancient DNA** (`--ancient_dna`): rewires the inputs of 40+ rules (skips host removal, phiX removal and assembly) for a niche parameter — would double the rule graph for an off-by-default mode.
- **CAT/BAT** (`--cat_db`): needs the CAT-nr database (~35 GB) and a MASH sketch downloaded/generated at run time.
- **Virus identification** (`--virus_identification`): needs the genomad database (~10 GB) downloaded at run time.
- **Pydamage, CheckM2 and GUNC report pages**: report-only artifacts of tools that are themselves not ported (above).
- **BUSCO `*-busco.batch_summary.failed.txt`**: only exists upstream when a BUSCO run failed — an error-only artifact.
- **nf-core boilerplate files** (pipeline_summary/methods_description, versions.yml): not analysis output.

## Test

```bash
bash test/run.sh    # static acceptance: validate + lint + dry-run + debug
```

The acceptance test needs only `oxo-flow` (v0.12.0+) on `PATH` (override with `OXO=/path/to/oxo-flow`); no conda environments or databases are required for validation.

**Status: live-verified on bioinfo-wsx** (real metagenome reference data, `run_gtdbtk=false` — the documented live-test contract, since a real GTDB-Tk run needs the ~100 GB reference database). Live queue results:

| Toggle | Result |
|---|---|
| default | ✅ PASS |
| `clip_tool=trimmomatic` | ✅ PASS |
| `bbnorm=true` | ✅ PASS |
| `refine_bins_dastool=true` | ✅ PASS (MEGAHIT + SPAdes, MetaBAT2/COMEBin/SemiBin2/… binning + DASTool refinement) |
| `run_checkm=true` | ✅ PASS (quast + CheckM lineage_wf on all bin sets) |
| `bin_domain_classification=true` | ✅ PASS (TIARA_TIARA per-contig + TIARA_CLASSIFY per bin set; zero-classified sets emit an empty tsv — live-verified guard, see commit b67191b) |

The remaining when-gated branches are statically verified: `validate` + `lint` + `dry-run` confirm each gate activates exactly its own branch with the default plan unchanged (see the gated-branches table). Runtime behavior of the underlying tools is unchanged from upstream nf-core/mag.

## License

Apache-2.0 for this workflow (see [LICENSE](LICENSE)). This port is derived from [nf-core/mag](https://github.com/nf-core/mag) under the MIT license — the upstream LICENSE is included verbatim in [LICENSE.upstream](LICENSE.upstream); see [NOTICE.md](NOTICE.md) for attribution.
