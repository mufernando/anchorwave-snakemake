# AnchorWave Snakemake Pipeline

Pairwise whole-genome alignment of **N target genomes** to one **annotated reference** using
[AnchorWave](https://github.com/baoxingsong/AnchorWave).  Each target is aligned independently,
and the alignment mode (`genoAli` or `proali`) can be set per target.

## Overview

```
reference FASTA + GFF ──┐
                        ├─ gff2seq ─── CDS FASTA ──┐
                        ├─ minimap2 (ref) ──────────┤
                        │                           │
target₁ FASTA ──────────├─ minimap2 (target₁) ─────├─ anchorwave_align ─┬─ MAF / f.MAF
target₂ FASTA ──────────├─ minimap2 (target₂) ─────├─ anchorwave_align ─├─ anchor dotplot
  ...                   │    ...                    │    ...             ├─ summary stats
targetN FASTA ──────────└─ minimap2 (targetN) ─────└─ anchorwave_align ─┘
                                                                        └─ results/summary.tsv
```

## Quick start

### 1. Install the conda environment

```bash
mamba env create -p /path/to/envs/anchorwave -f environment.yaml
```

On a cluster, follow its profile's instructions instead (see [Cluster profiles](#cluster-profiles)).

### 2. Edit the configuration

**`config/config.yaml`** — set the reference genome paths:

```yaml
reference:
  name: "B73"
  fasta: "/path/to/B73.fa"
  gff: "/path/to/B73.gff3"
```

The GFF must be uncompressed, and its seqids must match the first word of each FASTA header
(headers are trimmed to the first word during staging).

**`config/targets.tsv`** — one row per target genome:

| column | required | description |
|---|---|---|
| `sample` | yes | Unique target ID (alphanumeric, `_`, `.`, `-`) |
| `fasta` | yes | Path to the target FASTA (`.fa`/`.fasta`, optionally `.gz`) |
| `mode` | no | `genoAli` (default) or `proali` |
| `proali_R` | if proali | Max reference-side alignment coverage (`-R`) |
| `proali_Q` | if proali | Max target-side alignment coverage (`-Q`) |
| `extra` | no | Extra AnchorWave flags for this target only |
| *any other* | no | Metadata (e.g. species, status). Shown in the QC HTML report; not used by the pipeline |

Example:

```
sample	fasta	mode	proali_R	proali_Q	extra
Mo17	/data/Mo17.fa.gz	genoAli
B97	/data/B97.fa	genoAli
Sbicolor	/data/Sbicolor_v3.fa	proali	1	2
```

#### Using a different config or targets sheet

You don't have to edit `config/config.yaml`. Pass your own config with `--configfile`. It is merged on top of `config/config.yaml`, and any key you leave out keeps its default:

```bash
snakemake --configfile config/mex-admix.yaml --profile profiles/<cluster>
```

The targets sheet comes from the `targets:` key. Set it in your config YAML, or override it on the command line (`--config` takes precedence over both YAML files):

```bash
snakemake --configfile config/mex-admix.yaml --config targets=config/other.tsv --profile profiles/<cluster>
```

> **Note:** give each config its own `outdir` (e.g. `results/mex-admix`) so runs don't overwrite each other's outputs.

### 3. Check the CDS dotplots and choose each target's mode

Before the long AnchorWave runs, map the CDS and plot a dotplot for each target:

```bash
snakemake dotplots --profile profiles/<cluster>
```

This runs staging, `gff2seq`, and `minimap2` only. It writes one 300 dpi PNG per target and
collates them in `results/qc/cds_dotplots.html`, one page you can scroll or filter, with each
target's metadata from the targets sheet.
Each point is one reference CDS at its primary hit in the reference (x) and the target (y).
Use the plots to set `mode` in `config/targets.tsv` (see [Alignment modes](#alignment-modes)).

To group the targets in the report by one column of the targets sheet, set it in the config:

```yaml
qc_report:
  group_by: "Status"
```

### 4. Run the pipeline

From the repository root, with the environment activated:

```bash
snakemake -n                         # dry run to check the DAG
snakemake --profile profiles/<cluster>
```

Outputs from the `dotplots` step are reused, not recomputed.

Rule logs go to `logs/` in the working directory, not under `results/`.

### 5. Outputs

```
results/
├── genomes/            # Staged (decompressed, header-trimmed) FASTAs
├── reference/
│   └── cds.fa          # CDS sequences from the reference
├── sam/                # minimap2 CDS-to-genome SAM files
├── align/{target}/     # Per-target AnchorWave outputs
│   ├── {target}.maf        # Whole-genome alignment
│   ├── {target}.f.maf      # Fragmented alignment
│   └── {target}.anchors    # Collinear anchors
├── qc/
│   ├── README.md                   # List of the files in qc/
│   ├── cds_dotplots.html           # All CDS dotplots, with metadata (from the `dotplots` step)
│   ├── index.html                  # CDS and anchor dotplots side by side, with metadata
│   ├── {target}.cds_dotplot.png    # Pre-alignment CDS dotplot (from minimap2), 300 dpi
│   ├── {target}.anchors.png        # Anchor dotplot, 300 dpi
│   ├── preview/                    # Low-resolution copies shown on the HTML pages
│   └── {target}.summary.tsv        # Per-target alignment stats
└── summary.tsv         # Combined summary table (all targets)
```

The HTML pages link their images by relative path, so `results/qc/` can be copied to a web
server as a whole, for example:

```bash
rsync -a results/qc/ ~/public_html/<project>/
```

The trailing slash on `results/qc/` copies its contents rather than the folder itself.
Files deleted from `results/qc/` stay on the web server; add `--delete` only if the
destination should mirror `results/qc/` exactly. The pages leave out the `fasta` column.

## Resource defaults

Each rule has default `threads`, `mem_mb`, and `runtime` values in `config/config.yaml`
under `resources:`. Override them there or via `--default-resources` / `--set-resources`
on the command line. The Slurm account and partition are **not** set by the pipeline; they
come from the cluster profile.

| Rule | Threads | Memory | Time |
|---|---|---|---|
| stage_fasta | 1 | 4 GB | 1 h |
| stage_gff | 1 | 2 GB | 30 min |
| faidx | 1 | 2 GB | 30 min |
| gff2seq | 1 | 8 GB | 1 h |
| minimap2_cds | 8 | 32 GB | 6 h |
| anchorwave_align | 16 | 248 GB | 3 days |
| plot_cds_dotplot | 1 | 8 GB | 30 min |
| plot_anchors | 1 | 8 GB | 30 min |
| summarize_maf | 1 | 16 GB | 2 h |
| aggregate_summary | 1 | 2 GB | 10 min |

For very large genomes (>2 Gb), increase `anchorwave_align` memory and time, keeping within
your cluster account's per-job limits.

## Cluster profiles

Cluster-specific settings (executor, Slurm account and partition, filesystem latency) live in
`profiles/<cluster>/`:

- [`profiles/hive/`](profiles/hive/README.md): UC Davis Hive

## Alignment modes

Choose per target from its CDS dotplot:

- One diagonal per chromosome pair, with inverted (red) segments at most: `genoAli`.
- Blocks off the diagonal or on another chromosome (translocations), or repeated blocks
  (duplications, ploidy differences): `proali`.

When in doubt, use `proali`: it handles rearrangements, while `genoAli` assumes collinearity.

The plot uses primary minimap2 hits only. Set `cds_dotplot.min_mapq` in `config/config.yaml` to
hide multi-copy genes; the default of 0 keeps them, so duplicated blocks stay visible.

- **genoAli**: for genomes collinear with the reference and the same ploidy.
  Passes `-IV` by default to allow inversions (configurable via `genoali.inversions`).
- **proali**: for targets with whole-genome duplication or different ploidy relative to
  the reference. Requires `proali_R` and `proali_Q` in the sample sheet.

## Acknowledgments

Claude Opus 5.5 (Anthropic) was used in the development of the pipeline.

