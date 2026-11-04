"""check_chroms.py — Check that a genoAli target uses the reference's sequence names.

AnchorWave genoAli aligns only sequences with the same name in the reference and target,
so the reference names are taken as the truth:
- error if the target shares no sequence names with the reference;
- warning if the target lacks a reference sequence at least as long as the shortest
  sequence it does share (e.g. a missing or misnamed chromosome).

Called by Snakemake: snakemake.input, snakemake.output, snakemake.params, snakemake.log.
Uses only the Python standard library.
"""

import sys

log = open(snakemake.log[0], "w")
target = snakemake.params.target
reference = snakemake.params.reference


def report(msg):
    """Write to the rule log and to the terminal running Snakemake (this is a local rule)."""
    for fh in (log, sys.__stderr__):
        print(msg, file=fh, flush=True)


def parse_fai(fai_path):
    """Read a .fai and return {name: length}, in file order."""
    lengths = {}
    with open(fai_path) as fh:
        for line in fh:
            parts = line.split("\t")
            lengths[parts[0]] = int(parts[1])
    return lengths


def preview(names, n=10):
    """First n names, comma-separated, with a count of the rest."""
    names = list(names)
    more = f", ... ({len(names) - n} more)" if len(names) > n else ""
    return ", ".join(names[:n]) + more


ref = parse_fai(snakemake.input.ref_fai)
tgt = parse_fai(snakemake.input.target_fai)
shared = [name for name in ref if name in tgt]

if not shared:
    largest = sorted(tgt, key=tgt.get, reverse=True)
    report(
        f"ERROR [check_chroms] {target}: no sequence names in common with reference "
        f"'{reference}', so genoAli would align nothing.\n"
        f"  reference: {preview(sorted(ref, key=ref.get, reverse=True))}\n"
        f"  {target}: {preview(largest)}\n"
        f"  Rename the target's sequences to match the reference, or use proali."
    )
    sys.exit(1)

shortest_shared = min(ref[name] for name in shared)
missing = [name for name in ref if name not in tgt and ref[name] >= shortest_shared]
ref_total = sum(ref.values())
shared_bp = sum(ref[name] for name in shared)

report(
    f"[check_chroms] {target}: {len(shared)} of {len(ref)} reference sequences found "
    f"({shared_bp / ref_total:.1%} of reference bases)."
)
if missing:
    report(
        f"WARNING [check_chroms] {target}: missing {len(missing)} reference sequence(s) at "
        f"least as long as the shortest shared one ({shortest_shared:,} bp); these will not "
        f"be aligned: {preview(missing)}"
    )

with open(snakemake.output.tsv, "w") as fh:
    print("sequence\tlength\tin_target", file=fh)
    for name, length in ref.items():
        print(f"{name}\t{length}\t{'yes' if name in tgt else 'no'}", file=fh)
