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

On Hive, build the env inside a job (not on the login node):

```bash
srun -A <ACCOUNT> -p high -t 1:00:00 -c 2 --mem=16G --pty bash -l
module load conda
mamba env create -p /quobyte/<PIGRP>/$USER/envs/anchorwave -f environment.yaml
```

### 2. Edit the configuration

**`config/config.yaml`** — set the reference genome paths:

```yaml
reference:
  name: "B73"
  fasta: "/path/to/B73.fa"
  gff: "/path/to/B73.gff3"
```

**`config/targets.tsv`** — one row per target genome:

| column | required | description |
|---|---|---|
| `sample` | yes | Unique target ID (alphanumeric, `_`, `.`, `-`) |
| `fasta` | yes | Path to the target FASTA (`.fa`/`.fasta`, optionally `.gz`) |
| `mode` | no | `genoAli` (default) or `proali` |
| `proali_R` | if proali | Max reference-side alignment coverage (`-R`) |
| `proali_Q` | if proali | Max target-side alignment coverage (`-Q`) |
| `extra` | no | Extra AnchorWave flags for this target only |

Example:

```
sample	fasta	mode	proali_R	proali_Q	extra
Mo17	/data/Mo17.fa.gz	genoAli
B97	/data/B97.fa	genoAli
Sbicolor	/data/Sbicolor_v3.fa	proali	2	1	-ns
```

### 3. Run the pipeline

Activate the environment and run with the Slurm executor:

```bash
conda activate /quobyte/<PIGRP>/$USER/envs/anchorwave

# Dry run to check the DAG
snakemake -n

# Run with Slurm (inside tmux on the login node)
snakemake --executor slurm \
    --default-resources slurm_account=<ACCOUNT> slurm_partition=high \
    --jobs 10
```

Or submit the controller itself as a job:

```bash
sbatch --account=<ACCOUNT> --partition=high --time=7-00:00:00 \
    --cpus-per-task=1 --mem=4G --job-name=anchorwave-smk \
    --output=snakemake-%j.out --error=snakemake-%j.err \
    --wrap "snakemake --executor slurm \
        --default-resources slurm_account=<ACCOUNT> slurm_partition=high \
        --jobs 10"
```

### 4. Outputs

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
│   ├── {target}.anchors.png    # Anchor dotplot
│   └── {target}.summary.tsv   # Per-target alignment stats
└── summary.tsv         # Combined summary table (all targets)
```

## Resource defaults

Each rule has default `threads`, `mem_mb`, and `runtime` values in `config/config.yaml`
under `resources:`. Override them there or via `--default-resources` / `--set-resources`
on the command line. The Slurm account and partition are **not** set by the pipeline — pass
them via `--default-resources` or a Snakemake profile.

| Rule | Threads | Memory | Time |
|---|---|---|---|
| stage_fasta | 1 | 4 GB | 1 h |
| faidx | 1 | 2 GB | 30 min |
| gff2seq | 1 | 8 GB | 1 h |
| minimap2_cds | 8 | 32 GB | 6 h |
| anchorwave_align | 4 | 128 GB | 3 days |
| plot_anchors | 1 | 8 GB | 30 min |
| summarize_maf | 1 | 8 GB | 30 min |

For very large genomes (>2 Gb), increase `anchorwave_align` memory and time.

## Alignment modes

- **genoAli**: for genomes collinear with the reference and the same ploidy.
  Passes `-IV` by default to allow inversions (configurable via `genoali.inversions`).
- **proali**: for targets with whole-genome duplication or different ploidy relative to
  the reference. Requires `proali_R` and `proali_Q` in the sample sheet.
