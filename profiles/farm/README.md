# Farm profile

Snakemake profile for the UC Davis [Farm](https://docs.hpc.ucdavis.edu/farm/) cluster,
following the RILAB [Using Farm](https://github.com/RILAB/lab-docs/wiki/Using-Farm) wiki.

`config.yaml` sets the Slurm executor, account `jrigrp` on partition `high`, and
`latency-wait: 60`. Quobyte is a network filesystem, so outputs written on compute nodes can
take a while to appear; with a shorter wait, Snakemake can report finished outputs as missing.

- Always use account `jrigrp`. The default account, `publicgrp`, can only use `low`, and
  `high` without `jrigrp` fails with `Invalid account or account/partition combination specified`.
- `high` is lab-owned and not preempted, with a shared lab limit of 608 CPUs and 1,372 GB RAM.
  Nodes have 256–512 GB, so the 248 GB `anchorwave_align` default fits. Before using more than
  100 CPUs or 256 GB in total, check current usage and post in `#farm_issues` on Slack.
  With `jobs: 10`, ten concurrent alignments at 16 threads / 248 GB exceed that, so lower
  `jobs` (e.g. `--jobs 1`) for alignment-heavy runs or ask first.
- `low` holds the 1–2 TB big-memory nodes (there is no bigmem partition any more), but jobs
  there can be killed and requeued from the start, with a 7-day limit. Use it only for jobs
  over ~500 GB, e.g. per rule:
  `--set-resources anchorwave_align:slurm_partition=low anchorwave_align:mem_mb=800000`.
- The `med`, `bigmem*`, `bmm`, and `*2` partitions were removed in December 2025.

## 1. Build the environment

Keep conda/micromamba envs and package caches on group storage, not the 20 GB home, e.g. in
`~/.bashrc`:

```bash
export CONDA_PKGS_DIRS=/quobyte/jrigrp/$USER/.conda/pkgs
```

Build it in a job, not on the login node:

```bash
srun -A jrigrp -p high -t 1:00:00 -c 2 --mem=16G --pty bash -l
micromamba create -n anchorwave -f environment.yaml
```

## 2. Run

Run the controller inside `tmux` on the login node, from the repository root, so it survives
disconnects. It submits each rule as its own Slurm job:

```bash
tmux new -s anchorwave
micromamba activate anchorwave
snakemake --profile profiles/farm
```
