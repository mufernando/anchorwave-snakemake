# AnchorWave QC dotplots

Dotplots of {n_targets} target genomes against the reference **{reference}**.
Targets come from `{targets_sheet}`. Generated {generated}.

| File | What it is |
|---|---|
| `cds_dotplots.html` | CDS dotplots of every target, made before alignment |
| `index.html` | CDS and anchor dotplots side by side, made after alignment |
| `{{target}}.cds_dotplot.png` | CDS dotplot for one target, 300 dpi |
| `{{target}}.anchors.png` | Anchor dotplot for one target, 300 dpi |
| `preview/` | Low-resolution copies of the PNGs, shown on the HTML pages |
| `{{target}}.summary.tsv` | Alignment statistics for one target |
