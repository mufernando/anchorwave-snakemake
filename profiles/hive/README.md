# Hive profile

Slurm profile for UC Davis [Hive](https://docs.hpc.ucdavis.edu/hive/): account
`genome-center-grp`, partition `high`, and `latency-wait: 60` because Quobyte can be slow to
show new files. Change the account in `config.yaml` if you use another. The free tier
(`publicgrp`) caps jobs at 8 CPUs / 128 GB, too small for `anchorwave_align` (16 threads, 248 GB).

## Usage

Create the environment in a job rather than on the login node
(`srun -A genome-center-grp -p high -t 1:00:00 -c 2 --mem=16G --pty bash -l`), with envs and
package caches on group storage, not the 20 GB home.

Run the controller in `tmux` on the login node, from the repository root:

```bash
snakemake --profile profiles/hive
```
