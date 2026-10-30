# Hive profile

Snakemake profile for the UC Davis [Hive](https://docs.hpc.ucdavis.edu/hive/) cluster.

`config.yaml` sets the Slurm executor, account and partition, and `latency-wait: 60`.
Quobyte is a network filesystem, so outputs written on compute nodes can take a while to
appear; with a shorter wait, Snakemake can report finished outputs as missing.

It uses account `genome-center-grp` on partition `high`; change it there if you use a
different account. On the free tier (`publicgrp`), each job on `high` is capped at
8 CPUs and 128 GB. `anchorwave_align` defaults to 16 threads and 248 GB, so it needs a
PI group's account; 248 GB is close to the 250 GB of a standard `high` node.

## 1. Build the environment

Build it in a job, not on the login node:

```bash
srun -A genome-center-grp -p high -t 1:00:00 -c 2 --mem=16G --pty bash -l
micromamba create -n anchorwave -f environment.yaml
```

Keep micromamba's root prefix (and so its envs and package cache) on group storage, not in
the 20 GB home directory.

## 2. Run

Run the controller inside `tmux` on the login node, from the repository root, so it survives
disconnects. It submits each rule as its own Slurm job:

```bash
tmux new -s anchorwave
micromamba activate anchorwave
snakemake --profile profiles/hive
```
