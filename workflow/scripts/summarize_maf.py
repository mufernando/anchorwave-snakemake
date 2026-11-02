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
    # One byte per reference base, set once it is aligned to a target base.
    # proali with -R > 1 can align a reference base in several blocks; count it once.
    covered = {}

    def flush(block_lines):
        nonlocal ref_aligned_bp, identical_bp, ref_gap_bp, target_gap_bp
        stats = _process_block(block_lines, ref_lengths, covered)
        ref_aligned_bp += stats["ref_aligned"]
        identical_bp += stats["identical"]
        ref_gap_bp += stats["ref_gaps"]
        target_gap_bp += stats["target_gaps"]

    with open(maf_path) as fh:
        block_lines = []
        for line in fh:
            if line.startswith("a"):
                if block_lines:
                    flush(block_lines)
                block_lines = []
                n_blocks += 1
            elif line.startswith("s"):
                block_lines.append(line)
            elif line.strip() == "" and block_lines:
                flush(block_lines)
                block_lines = []

        if block_lines:
            flush(block_lines)

    ref_total = sum(ref_lengths.values())
    ref_covered_bp = sum(c.count(1) for c in covered.values())
    identity = identical_bp / ref_aligned_bp if ref_aligned_bp > 0 else 0.0
    coverage = ref_covered_bp / ref_total if ref_total > 0 else 0.0

    return {
        "alignment_blocks": n_blocks,
        "ref_aligned_bp": ref_aligned_bp,
        "identical_bp": identical_bp,
        "identity": round(identity, 6),
        "ref_covered_bp": ref_covered_bp,
        "ref_total_bp": ref_total,
        "ref_coverage": round(coverage, 6),
        "ref_gap_bp": ref_gap_bp,
        "target_gap_bp": target_gap_bp,
    }


def _process_block(s_lines, ref_lengths, covered):
    """Process the s-lines of one alignment block, marking covered reference bases."""
    stats = {"ref_aligned": 0, "identical": 0, "ref_gaps": 0, "target_gaps": 0}
    if len(s_lines) < 2:
        return stats

    # Parse the two s-lines (reference, then target)
    _, chrom, start, _, strand, src_size, ref_seq = s_lines[0].split()
    tgt_seq = s_lines[1].split()[6]

    if chrom not in ref_lengths:
        raise ValueError(f"MAF reference sequence '{chrom}' is not in the reference .fai")
    if chrom not in covered:
        covered[chrom] = bytearray(ref_lengths[chrom])
    cov = covered[chrom]

    # Forward-strand position of the next reference base
    if strand == "+":
        pos, step = int(start), 1
    else:
        pos, step = int(src_size) - 1 - int(start), -1

    aligned = identical = ref_gaps = target_gaps = 0
    for r, t in zip(ref_seq, tgt_seq):
        if r == "-":
            if t != "-":
                ref_gaps += 1
            continue
        if t == "-":
            target_gaps += 1
        else:
            aligned += 1
            cov[pos] = 1
            if r.upper() == t.upper():
                identical += 1
        pos += step

    stats["ref_aligned"] = aligned
    stats["identical"] = identical
    stats["ref_gaps"] = ref_gaps
    stats["target_gaps"] = target_gaps
    return stats


def main():
    maf_path = snakemake.input["maf"]
    fai_path = snakemake.input["ref_fai"]
    out_path = snakemake.output["tsv"]
    log_path = snakemake.log[0]

    # Extract target name from the wildcard
    target = snakemake.wildcards.target
    mode = snakemake.params["mode"]

    with open(log_path, "w") as log_fh:
        sys.stderr = log_fh
        try:
            ref_lengths = parse_fai(fai_path)
            stats = summarize_maf(maf_path, ref_lengths)

            with open(out_path, "w") as out:
                cols = ["sample", "mode", "alignment_blocks", "ref_aligned_bp",
                        "identical_bp", "identity", "ref_covered_bp",
                        "ref_total_bp", "ref_coverage", "ref_gap_bp",
                        "target_gap_bp"]
                out.write("\t".join(cols) + "\n")
                vals = [target, mode, stats["alignment_blocks"],
                        stats["ref_aligned_bp"], stats["identical_bp"],
                        stats["identity"], stats["ref_covered_bp"],
                        stats["ref_total_bp"], stats["ref_coverage"],
                        stats["ref_gap_bp"], stats["target_gap_bp"]]
                out.write("\t".join(str(v) for v in vals) + "\n")

            print(f"Done: {target}", file=log_fh)
        except Exception as e:
            print(f"ERROR: {e}", file=log_fh)
            raise


main()
