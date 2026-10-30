"""summarize_maf.py — Compute alignment statistics from a MAF file.

Called by Snakemake: snakemake.input, snakemake.output, snakemake.log.
Uses only the Python standard library.
"""

import sys
from pathlib import Path


def parse_fai(fai_path):
    """Read a .fai and return {chrom: length}."""
    lengths = {}
    with open(fai_path) as fh:
        for line in fh:
            parts = line.split("\t")
            lengths[parts[0]] = int(parts[1])
    return lengths


def summarize_maf(maf_path, ref_lengths):
    """Parse a MAF file and compute summary statistics."""
    n_blocks = 0
    ref_aligned_bp = 0
    identical_bp = 0
    ref_gap_bp = 0
    target_gap_bp = 0

    with open(maf_path) as fh:
        block_lines = []
        for line in fh:
            if line.startswith("a"):
                # Start of a new alignment block
                if block_lines:
                    _process_block(block_lines, ref_aligned_bp, identical_bp,
                                   ref_gap_bp, target_gap_bp)
                block_lines = []
                n_blocks += 1
            elif line.startswith("s"):
                block_lines.append(line)
            elif line.strip() == "" and block_lines:
                stats = _process_block(block_lines)
                ref_aligned_bp += stats["ref_aligned"]
                identical_bp += stats["identical"]
                ref_gap_bp += stats["ref_gaps"]
                target_gap_bp += stats["target_gaps"]
                block_lines = []

        # Handle last block
        if block_lines:
            stats = _process_block(block_lines)
            ref_aligned_bp += stats["ref_aligned"]
            identical_bp += stats["identical"]
            ref_gap_bp += stats["ref_gaps"]
            target_gap_bp += stats["target_gaps"]

    ref_total = sum(ref_lengths.values())
    identity = identical_bp / ref_aligned_bp if ref_aligned_bp > 0 else 0.0
    coverage = ref_aligned_bp / ref_total if ref_total > 0 else 0.0

    return {
        "alignment_blocks": n_blocks,
        "ref_aligned_bp": ref_aligned_bp,
        "identical_bp": identical_bp,
        "identity": round(identity, 6),
        "ref_total_bp": ref_total,
        "ref_coverage": round(coverage, 6),
        "ref_gap_bp": ref_gap_bp,
        "target_gap_bp": target_gap_bp,
    }


def _process_block(s_lines):
    """Process the s-lines of one alignment block."""
    stats = {"ref_aligned": 0, "identical": 0, "ref_gaps": 0, "target_gaps": 0}
    if len(s_lines) < 2:
        return stats

    # Parse the two s-lines (reference, then target)
    ref_parts = s_lines[0].split()
    tgt_parts = s_lines[1].split()
    ref_seq = ref_parts[6]
    tgt_seq = tgt_parts[6]

    for r, t in zip(ref_seq, tgt_seq):
        r_gap = r == "-"
        t_gap = t == "-"
        if r_gap and t_gap:
            continue
        elif r_gap:
            stats["ref_gaps"] += 1
        elif t_gap:
            stats["target_gaps"] += 1
        else:
            stats["ref_aligned"] += 1
            if r.upper() == t.upper():
                stats["identical"] += 1

    return stats


def main():
    maf_path = snakemake.input["maf"]
    fai_path = snakemake.input["ref_fai"]
    out_path = snakemake.output["tsv"]
    log_path = snakemake.log[0]

    # Extract target name from the wildcard
    target = snakemake.wildcards.target

    with open(log_path, "w") as log_fh:
        sys.stderr = log_fh
        try:
            ref_lengths = parse_fai(fai_path)
            stats = summarize_maf(maf_path, ref_lengths)

            with open(out_path, "w") as out:
                cols = ["sample", "alignment_blocks", "ref_aligned_bp",
                        "identical_bp", "identity", "ref_total_bp",
                        "ref_coverage", "ref_gap_bp", "target_gap_bp"]
                out.write("\t".join(cols) + "\n")
                vals = [target, stats["alignment_blocks"],
                        stats["ref_aligned_bp"], stats["identical_bp"],
                        stats["identity"], stats["ref_total_bp"],
                        stats["ref_coverage"], stats["ref_gap_bp"],
                        stats["target_gap_bp"]]
                out.write("\t".join(str(v) for v in vals) + "\n")

            print(f"Done: {target}", file=log_fh)
        except Exception as e:
            print(f"ERROR: {e}", file=log_fh)
            raise


main()
