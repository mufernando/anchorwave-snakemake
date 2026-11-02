"""
qc_report.py — Collate per-target dotplots and sample-sheet metadata into one HTML page.
Called by Snakemake: snakemake.input, snakemake.output, snakemake.params, snakemake.log

Images are linked by relative path, so the output directory can be copied (e.g. to a web
server) as a whole.  The page shows the low-resolution previews; clicking one opens the
full-resolution PNG.
"""

import html
import os
import sys
from datetime import datetime

sys.stderr = open(snakemake.log[0], "w")

out_file = snakemake.output.html
out_dir = os.path.dirname(os.path.abspath(out_file))
targets = snakemake.params.targets  # list of dicts, in sheet order
panels = snakemake.params.panels  # list of {"key": ..., "label": ...}
group_by = snakemake.params.group_by
title = snakemake.params.title
reference = snakemake.params.reference

esc = html.escape


def rel(path):
    return os.path.relpath(os.path.abspath(path), out_dir)


# Images per panel, keyed by target (inputs are expanded in the same order as `targets`)
images = {}
for panel in panels:
    plots = getattr(snakemake.input, f"{panel['key']}_plots")
    previews = getattr(snakemake.input, f"{panel['key']}_previews")
    for t, plot, preview in zip(targets, plots, previews):
        images[(t["sample"], panel["key"])] = (rel(plot), rel(preview))

# Groups in order of first appearance in the sheet
groups = {}
for t in targets:
    groups.setdefault(t["group"], []).append(t)


def search_text(t):
    values = [t["sample"]] + list(t["settings"].values()) + list(t["metadata"].values())
    return esc(" ".join(values).lower())


def target_section(t):
    name = t["sample"]
    badges = "".join(
        f'<span class="badge">{esc(k)}: {esc(v)}</span>' for k, v in t["settings"].items()
    )
    rows = "".join(
        f"<tr><th>{esc(k)}</th><td>{esc(v)}</td></tr>" for k, v in t["metadata"].items()
    )
    meta = f'<table class="meta">{rows}</table>' if rows else ""
    figures = []
    for panel in panels:
        plot, preview = images[(name, panel["key"])]
        figures.append(
            f'<figure><a href="{esc(plot)}" target="_blank">'
            f'<img src="{esc(preview)}" loading="lazy" alt="{esc(panel["label"])}: {esc(name)}">'
            f'</a><figcaption>{esc(panel["label"])}</figcaption></figure>'
        )
    return (
        f'<section class="target" id="t-{esc(name)}" data-search="{search_text(t)}">'
        f'<h3>{esc(name)} {badges}</h3>{meta}'
        f'<div class="figs cols-{len(panels)}">{"".join(figures)}</div></section>'
    )


nav = []
main = []
for group, members in groups.items():
    links = "".join(
        f'<li data-search="{search_text(t)}"><a href="#t-{esc(t["sample"])}">{esc(t["sample"])}</a></li>'
        for t in members
    )
    sections = "".join(target_section(t) for t in members)
    if group_by:
        nav.append(
            f'<div class="group"><h4>{esc(group)} <span class="n">({len(members)})</span></h4>'
            f"<ul>{links}</ul></div>"
        )
        main.append(f'<div class="group"><h2>{esc(group_by)}: {esc(group)}</h2>{sections}</div>')
    else:
        nav.append(f'<div class="group"><ul>{links}</ul></div>')
        main.append(f'<div class="group">{sections}</div>')

panel_labels = " and ".join(p["label"].lower() for p in panels)
generated = datetime.now().strftime("%Y-%m-%d %H:%M")

page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<style>
  :root {{ --sidebar: 15rem; --border: #ddd; --muted: #666; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
         font-size: 14px; color: #222; background: #fafafa; }}
  nav {{ position: fixed; top: 0; bottom: 0; left: 0; width: var(--sidebar);
        overflow-y: auto; padding: 1rem; background: #fff; border-right: 1px solid var(--border); }}
  nav input {{ width: 100%; padding: 0.4rem; margin-bottom: 0.75rem;
              border: 1px solid var(--border); border-radius: 4px; font: inherit; }}
  nav h4 {{ margin: 0.75rem 0 0.25rem; font-size: 0.8rem; text-transform: uppercase;
           letter-spacing: 0.04em; color: var(--muted); }}
  nav ul {{ list-style: none; margin: 0; padding: 0; }}
  nav li a {{ display: block; padding: 0.15rem 0.4rem; border-radius: 3px;
             color: #1a4f8b; text-decoration: none; }}
  nav li a:hover {{ background: #eef3f9; }}
  main {{ margin-left: var(--sidebar); padding: 1rem 2rem 4rem; max-width: 110rem; }}
  header p {{ margin: 0.25rem 0; color: var(--muted); }}
  h2 {{ margin: 2rem 0 0.5rem; padding-bottom: 0.25rem; border-bottom: 2px solid var(--border); }}
  .target {{ margin: 1rem 0; padding: 1rem; background: #fff;
            border: 1px solid var(--border); border-radius: 6px; scroll-margin-top: 1rem; }}
  .target h3 {{ margin: 0 0 0.5rem; }}
  .badge {{ display: inline-block; margin-left: 0.4rem; padding: 0.1rem 0.45rem;
           font-size: 0.75rem; font-weight: normal; background: #eef3f9;
           border-radius: 3px; color: #1a4f8b; vertical-align: middle; }}
  .meta {{ border-collapse: collapse; margin-bottom: 0.75rem; }}
  .meta th {{ text-align: left; padding: 0.1rem 1rem 0.1rem 0; font-weight: 600; color: var(--muted); }}
  .meta td {{ padding: 0.1rem 0; }}
  .figs {{ display: grid; gap: 1rem; }}
  .figs.cols-2 {{ grid-template-columns: 1fr 1fr; }}
  @media (max-width: 70rem) {{ .figs.cols-2 {{ grid-template-columns: 1fr; }} }}
  figure {{ margin: 0; }}
  figure img {{ width: 100%; height: auto; aspect-ratio: 14 / 12; display: block;
               border: 1px solid #eee; }}
  figcaption {{ margin-top: 0.25rem; font-size: 0.8rem; color: var(--muted); }}
  .hidden {{ display: none !important; }}
</style>
</head>
<body>
<nav>
  <input id="filter" type="search" placeholder="Filter targets…" autocomplete="off">
  {"".join(nav)}
</nav>
<main>
  <header>
    <h1>{esc(title)}</h1>
    <p>Reference: <strong>{esc(reference)}</strong> · {len(targets)} targets ·
       {esc(panel_labels)} · generated {generated}</p>
    <p>Click a plot to open it at full resolution.
       File list: <a href="README.md">README.md</a>.</p>
  </header>
  {"".join(main)}
</main>
<script>
  const filter = document.getElementById("filter");
  filter.addEventListener("input", () => {{
    const q = filter.value.trim().toLowerCase();
    document.querySelectorAll("[data-search]").forEach(el => {{
      el.classList.toggle("hidden", q !== "" && !el.dataset.search.includes(q));
    }});
    document.querySelectorAll(".group").forEach(g => {{
      g.classList.toggle("hidden", !g.querySelector("[data-search]:not(.hidden)"));
    }});
  }});
</script>
</body>
</html>
"""

with open(out_file, "w") as fh:
    fh.write(page)

print(f"Wrote {out_file}: {len(targets)} targets, {len(panels)} panel(s)", file=sys.stderr)
