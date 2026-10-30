rule plot_anchors:
    """Dotplot of collinear anchors for one target vs the reference."""
    input:
        anchors=f"{OUTDIR}/align/{{target}}/{{target}}.anchors",
    output:
        plot=f"{OUTDIR}/qc/{{target}}.anchors.png",
    log:
        f"logs/plot_anchors/{{target}}.log",
    threads: res("plot_anchors", "threads", 1)
    resources:
        mem_mb=res("plot_anchors", "mem_mb", 8192),
        runtime=res("plot_anchors", "runtime", 30),
    wildcard_constraints:
        target="|".join(TARGET_NAMES),
    script:
        "../scripts/plot_anchors.R"


rule summarize_maf:
    """Compute alignment statistics from a MAF file."""
    input:
        maf=f"{OUTDIR}/align/{{target}}/{{target}}.maf",
        ref_fai=staged_fai(REF_NAME),
    output:
        tsv=f"{OUTDIR}/qc/{{target}}.summary.tsv",
    log:
        f"logs/summarize_maf/{{target}}.log",
    threads: res("summarize_maf", "threads", 1)
    resources:
        mem_mb=res("summarize_maf", "mem_mb", 8192),
        runtime=res("summarize_maf", "runtime", 30),
    wildcard_constraints:
        target="|".join(TARGET_NAMES),
    script:
        "../scripts/summarize_maf.py"


rule aggregate_summary:
    """Combine per-target summaries into one table."""
    input:
        tsvs=expand(
            f"{OUTDIR}/qc/{{target}}.summary.tsv",
            target=TARGET_NAMES,
        ),
    output:
        tsv=f"{OUTDIR}/summary.tsv",
    log:
        "logs/aggregate_summary.log",
    run:
        import pandas as pd

        frames = []
        for f in input.tsvs:
            frames.append(pd.read_csv(f, sep="\t"))
        df = pd.concat(frames, ignore_index=True)
        df.to_csv(output.tsv, sep="\t", index=False)
