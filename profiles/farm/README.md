# Farm profile

Slurm profile for UC Davis [Farm](https://docs.hpc.ucdavis.edu/farm/): account `jrigrp`,
partition `high`, and `latency-wait: 60` because Quobyte can be slow to show new files.

- Use `jrigrp`. The default `publicgrp` can only use `low`.
- `high` is not preempted, but the lab shares 608 CPUs / 1,372 GB. Check usage and post in
  `#farm_issues` before using more than 100 CPUs or 256 GB; for alignment-heavy runs lower
  `jobs` (e.g. `--jobs 1`), since ten 248 GB alignments exceed the lab's share.
- Jobs over ~500 GB need the bigmem nodes, which `jrigrp` reaches only through `low`
  (preemptible, restarts from scratch):
  `--set-resources anchorwave_align:slurm_partition=low anchorwave_align:mem_mb=800000`.

## Usage

Create the environment in a job rather than on the login node
(`srun -A jrigrp -p high -t 1:00:00 -c 2 --mem=16G --pty bash -l`), with envs and package
caches under `/quobyte/jrigrp/$USER/`, not the 20 GB home.

Run the controller in `tmux` on the login node, from the repository root:

```bash
snakemake --profile profiles/farm
```
