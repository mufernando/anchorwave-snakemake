# AnchorWave Snakemake Pipeline

This pipeline aligns one or more target genomes to a single annotated reference genome using
[AnchorWave](https://github.com/baoxingsong/AnchorWave). Each target is aligned independently.
You can choose an alignment mode (`genoAli` or `proali`) for each target.

The workflow extracts coding sequences (CDS) from the reference annotation, maps them to the
reference and targets with minimap2, and uses those mappings to run AnchorWave. A pre-alignment
CDS dotplot helps you choose the alignment mode; the completed run also creates anchor dotplots
and summary statistics.

## Quick start

Run commands from the repository root. Input FASTA and GFF3 paths must be readable from the
machine that runs each job (including cluster compute nodes).

### 1. Create the software environment

The environment includes AnchorWave, minimap2, samtools, Snakemake, and the R packages used for
plots.

```bash
mamba env create -f environment.yaml
conda activate anchorwave
```

Conda can be used in place of mamba. `environment.yaml` specifies minimum package versions;
for exact package-version reproducibility across machines, use a platform-specific Conda lock
file.

### 2. Configure the reference and targets

Edit `config/config.yaml` to point to the reference FASTA and its GFF3 annotation:

```yaml
reference:
  name: "B73"
  fasta: "/path/to/B73.fa"
  gff: "/path/to/B73.gff3"

targets: "config/targets.tsv"
outdir: "results"
```

FASTA and GFF3 files may be plain text or gzip-compressed (`.gz`). During staging, the pipeline
decompresses compressed files and trims each FASTA header to its first whitespace-delimited
word. The first word of each reference FASTA header must match the corresponding sequence ID
in the GFF3 file.

Edit `config/targets.tsv` with one row per target genome:

| Column | Required? | Description |
|---|---|---|
| `sample` | Yes | Unique target ID; use letters, numbers, `_`, `.`, or `-`. It must differ from the reference name. |
| `fasta` | Yes | Path to the target FASTA (`.fa`/`.fasta`, optionally `.gz`). |
| `mode` | No | `genoAli` (default) or `proali`. |
| `proali_R`, `proali_Q` | For `proali` | Required positive values passed to AnchorWave as `-R` and `-Q`. |
| `extra` | No | Additional AnchorWave flags for this target. |
| Other columns | No | Metadata displayed in the QC HTML reports; not used for alignment. |

For example:

```text
sample	fasta	mode	proali_R	proali_Q	extra
Mo17	/data/Mo17.fa.gz	genoAli
Sbicolor	/data/Sbicolor_v3.fa	proali	1	2
```

### 3. Preview CDS dotplots and choose modes

Generate the pre-alignment dotplots before running the long alignments:

```bash
snakemake dotplots --cores 8
```

On a cluster, use the appropriate profile instead of `--cores 8`; for example:

```bash
snakemake dotplots --profile profiles/farm
```

Open `results/qc/cds_dotplots.html`. Each point represents a reference CDS at its primary
minimap2 hit in the reference and target. Use the overall pattern to choose a mode for each
target:

- Use `genoAli` when the pattern is mostly collinear (a diagonal for each corresponding
  chromosome/scaffold). Inversions are allowed by default.
- Use `proali` when there are substantial off-diagonal blocks, translocations, duplicated
  blocks, or ploidy differences. Set both `proali_R` and `proali_Q` in the targets sheet.
- If the pattern is unclear, investigate the genome and annotation or try `proali`; the
  dotplot is a guide, not a substitute for biological review.

The default `cds_dotplot.min_mapq: 0` includes multi-copy hits, which can reveal duplicated
blocks. Increase it in the config to filter out lower-quality hits. Set
`qc_report.group_by` to a targets-sheet column name to group samples in the HTML report.

### 4. Run the alignments

First check the jobs Snakemake plans, then run them:

```bash
snakemake -n --cores 8
snakemake --cores 8
```

For a cluster, use its Snakemake profile for both commands, for example:

```bash
snakemake -n --profile profiles/farm
snakemake --profile profiles/farm
```

The shipped profiles are configured for UC Davis Farm and Hive; see
[Farm](profiles/farm/README.md) and [Hive](profiles/hive/README.md) for account, partition, and
usage details. If you use another cluster, configure a profile for that cluster.

The full run reuses outputs from the dotplots step when they are up to date. Snakemake skips
outputs it considers current; use `--rerun-incomplete` to retry jobs whose outputs were left
incomplete by an interrupted run.

## Using a separate run configuration

To keep the defaults in `config/config.yaml` unchanged, create a second YAML config that
overrides the reference, target sheet, and output directory. For example:

```yaml
reference:
  name: "B73"
  fasta: "/data/B73.fa"
  gff: "/data/B73.gff3"

targets: "config/my-targets.tsv"
outdir: "results/my-run"
```

Pass it to Snakemake with `--configfile`:

```bash
snakemake -n --configfile config/my-run.yaml --cores 8
snakemake --configfile config/my-run.yaml --cores 8
```

Snakemake merges this file with the defaults in `config/config.yaml`; keys not specified in
the additional file keep their default values. You can also override the target sheet from
the command line with `--config targets=config/other-targets.tsv`. Use a distinct `outdir` for
each run so separate analyses do not overwrite each other's results. For repeatability, keep
the run config and targets sheet with records of the input assembly and annotation versions.

## Outputs and resources

By default, results are written under `results/`. Set `outdir` in the config to change this.

```text
results/
├── genomes/                  # Staged FASTA files
├── reference/                # Staged annotation and extracted CDS
├── sam/                      # minimap2 CDS-to-genome mappings
├── align/{target}/
│   ├── {target}.maf          # Whole-genome alignment
│   ├── {target}.f.maf        # Fragmented alignment
│   └── {target}.anchors      # Collinear anchors
├── qc/
│   ├── cds_dotplots.html     # Pre-alignment CDS dotplots
│   ├── index.html            # CDS and AnchorWave anchor dotplots
│   ├── {target}.summary.tsv  # Per-target statistics
│   └── ...                   # PNG plots, previews, and a QC file guide
└── summary.tsv               # Combined statistics for all targets
```

The HTML pages use relative links, so the complete `results/qc/` directory can be copied to
a web server to share the plots. The reports omit the targets-sheet `fasta` column.
Rule logs are written under `logs/` in the working directory.

Per-rule `threads`, `mem_mb`, and `runtime` defaults are in the `resources:` section of
`config/config.yaml` (memory is in MB and runtime is in minutes). Adjust these for your data
and cluster limits in a run-specific config or with Snakemake resource options. In particular,
large genomes may need more memory and time for `anchorwave_align`. On clusters, the profile
controls submission settings such as the Slurm account and partition; see the linked profile
guides before launching a large run.

## Alignment modes

- **`genoAli`** is intended for targets that are collinear with the reference and have the same
  ploidy. The pipeline passes AnchorWave's `-IV` flag by default to allow inversions; change
  this with `genoali.inversions`.
- **`proali`** is intended for more complex rearrangements or differences in ploidy. It
  requires positive `proali_R` and `proali_Q` values for each target using this mode.

Both modes accept additional AnchorWave options: use `genoali.extra` or `proali.extra` in the
config for options shared by that mode, or `extra` in the targets sheet for target-specific
options.

## Acknowledgments

Claude Opus 5.5 (Anthropic) was used in the development of the pipeline.
