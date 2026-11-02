# ── QC report helpers ───────────────────────────────────────────────────────
# Sample-sheet columns the pipeline itself uses; any other column is shown as metadata.
# fasta is left out of the report, which may be published on a public web server.
SETTINGS_COLUMNS = ["mode", "proali_R", "proali_Q", "extra"]
HIDDEN_COLUMNS = ["sample", "fasta"]
REPORT_GROUP_BY = config.get("qc_report", {}).get("group_by") or ""
if REPORT_GROUP_BY:
    assert REPORT_GROUP_BY in TARGETS.columns, (
        f"qc_report.group_by '{REPORT_GROUP_BY}' is not a column of the targets sheet"
    )


def report_targets():
    """Per-target settings and metadata for the QC report, in sheet order."""
    out = []
    for name, row in TARGETS.iterrows():
        cell = lambda col: "" if pd.isna(row[col]) else str(row[col]).strip()
        out.append(
            {
                "sample": name,
                "settings": {
                    c: cell(c) for c in SETTINGS_COLUMNS if c in row.index and cell(c)
                },
                "metadata": {
                    c: cell(c)
                    for c in TARGETS.columns
                    if c not in SETTINGS_COLUMNS + HIDDEN_COLUMNS and cell(c)
                },
                "group": (cell(REPORT_GROUP_BY) or "(none)") if REPORT_GROUP_BY else "",
            }
        )
    return out


def report_images(kind):
    """Full-resolution plots and previews of one kind ('cds_dotplot' or 'anchors')."""
    return {
        f"{kind}_plots": expand(f"{OUTDIR}/qc/{{target}}.{kind}.png", target=TARGET_NAMES),
        f"{kind}_previews": expand(
            f"{OUTDIR}/qc/preview/{{target}}.{kind}.png", target=TARGET_NAMES
        ),
    }


CDS_PANEL = {"key": "cds_dotplot", "label": "CDS dotplot (minimap2)"}
ANCHORS_PANEL = {"key": "anchors", "label": "Anchor dotplot (AnchorWave)"}


rule plot_cds_dotplot:
    """Pre-alignment dotplot of reference CDS hits in the reference vs one target."""
    input:
        ref_sam=f"{OUTDIR}/sam/{REF_NAME}.sam",
        target_sam=f"{OUTDIR}/sam/{{target}}.sam",
    output:
        plot=f"{OUTDIR}/qc/{{target}}.cds_dotplot.png",
        preview=f"{OUTDIR}/qc/preview/{{target}}.cds_dotplot.png",
    log:
        f"logs/plot_cds_dotplot/{{target}}.log",
    params:
        min_mapq=config.get("cds_dotplot", {}).get("min_mapq", 0),
    threads: res("plot_cds_dotplot", "threads", 1)
    resources:
        mem_mb=res("plot_cds_dotplot", "mem_mb", 8192),
        runtime=res("plot_cds_dotplot", "runtime", 30),
    wildcard_constraints:
        target="|".join(TARGET_NAMES),
    script:
        "../scripts/plot_cds_dotplot.R"


rule plot_anchors:
    """Dotplot of collinear anchors for one target vs the reference."""
    input:
        anchors=f"{OUTDIR}/align/{{target}}/{{target}}.anchors",
    output:
        plot=f"{OUTDIR}/qc/{{target}}.anchors.png",
        preview=f"{OUTDIR}/qc/preview/{{target}}.anchors.png",
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


# The report rules only write a small HTML file, so they run locally, not as cluster jobs.
localrules:
    qc_readme,
    qc_report_cds,
    qc_report,


rule qc_readme:
    """README for the QC output folder, listing its files."""
    input:
        template=workflow.source_path("../report/qc_README.md"),
        sheet=config["targets"],
    output:
        md=f"{OUTDIR}/qc/README.md",
    params:
        reference=REF_NAME,
        targets_sheet=config["targets"],
        n_targets=len(TARGET_NAMES),
    run:
        from datetime import datetime

        values = {
            "reference": params.reference,
            "targets_sheet": params.targets_sheet,
            "n_targets": str(params.n_targets),
            "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        }
        text = open(input.template).read()
        for key, value in values.items():
            text = text.replace("{" + key + "}", value)
        # {{target}} in the template is a literal placeholder for the target name
        text = text.replace("{{target}}", "{target}")
        with open(output.md, "w") as fh:
            fh.write(text)


rule qc_report_cds:
    """HTML page of every target's CDS dotplot and sample-sheet metadata (pre-alignment)."""
    input:
        sheet=config["targets"],
        **report_images("cds_dotplot"),
    output:
        html=f"{OUTDIR}/qc/cds_dotplots.html",
    log:
        "logs/qc_report_cds.log",
    params:
        targets=report_targets(),
        panels=[CDS_PANEL],
        group_by=REPORT_GROUP_BY,
        title="CDS dotplots",
        reference=REF_NAME,
    script:
        "../scripts/qc_report.py"


rule qc_report:
    """HTML page of every target's CDS and anchor dotplots side by side, with metadata."""
    input:
        sheet=config["targets"],
        **report_images("cds_dotplot"),
        **report_images("anchors"),
    output:
        html=f"{OUTDIR}/qc/index.html",
    log:
        "logs/qc_report.log",
    params:
        targets=report_targets(),
        panels=[CDS_PANEL, ANCHORS_PANEL],
        group_by=REPORT_GROUP_BY,
        title="AnchorWave QC dotplots",
        reference=REF_NAME,
    script:
        "../scripts/qc_report.py"


rule summarize_maf:
    """Compute alignment statistics from a MAF file."""
    input:
        maf=f"{OUTDIR}/align/{{target}}/{{target}}.maf",
        ref_fai=staged_fai(REF_NAME),
    output:
        tsv=f"{OUTDIR}/qc/{{target}}.summary.tsv",
    log:
        f"logs/summarize_maf/{{target}}.log",
    params:
        mode=lambda wc: TARGETS.loc[wc.target, "mode"],
    threads: res("summarize_maf", "threads", 1)
    resources:
        mem_mb=res("summarize_maf", "mem_mb", 16384),
        runtime=res("summarize_maf", "runtime", 120),
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
    threads: res("aggregate_summary", "threads", 1)
    resources:
        mem_mb=res("aggregate_summary", "mem_mb", 2048),
        runtime=res("aggregate_summary", "runtime", 10),
    run:
        import pandas as pd

        frames = []
        for f in input.tsvs:
            frames.append(pd.read_csv(f, sep="\t"))
        df = pd.concat(frames, ignore_index=True)
        df.to_csv(output.tsv, sep="\t", index=False)
