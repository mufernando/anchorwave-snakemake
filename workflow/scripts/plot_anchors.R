# plot_anchors.R — Dotplot of AnchorWave anchor positions
# Called by Snakemake: snakemake@input, snakemake@output, snakemake@log
#
# Writes the full-resolution plot and a low-resolution preview for the QC HTML report.

log_con <- file(snakemake@log[[1]], open = "wt")
sink(log_con, type = "message")
sink(log_con, type = "output")

library(data.table)
library(ggplot2)

anchors_file <- snakemake@input[["anchors"]]
out_file     <- snakemake@output[["plot"]]
preview_file <- snakemake@output[["preview"]]
target_name  <- snakemake@wildcards[["target"]]

plot_width  <- 14
plot_height <- 12
plot_dpi    <- 300
preview_dpi <- 72

# AnchorWave .anchors is tab-separated:
# refChr  referenceStart  referenceEnd  queryChr  queryStart  queryEnd  strand  gene  blockIndex  score
# with a leading "#anchorwave ..." command line and "#block begin/end" lines between blocks
lines <- readLines(anchors_file)
dt <- fread(text = lines[!startsWith(lines, "#")], header = TRUE, sep = "\t")
rm(lines)

# Normalize column names (different AnchorWave versions may differ)
# Use positional fallback if the expected names aren't found
expected <- c("referenceChromosome", "referenceStart", "referenceEnd",
              "queryChromosome", "queryStart", "queryEnd", "strand")
if (!all(expected %in% names(dt))) {
    # Positional: cols 1-7
    setnames(dt, seq_along(expected), expected)
}

# "interanchor" rows are the gaps between anchors, not anchors
if ("gene" %in% names(dt)) dt <- dt[gene != "interanchor"]
message(sprintf("Anchors: %d", nrow(dt)))

# Natural sort: chr1, chr2, ..., chr10, then scaf_1, scaf_2, ...
natural_sort <- function(x) {
    prefix <- sub("[0-9].*$", "", x)
    num    <- suppressWarnings(as.numeric(sub("^[^0-9]*([0-9]+).*$", "\\1", x)))
    x[order(prefix, num, x, method = "radix")]
}

if (nrow(dt) == 0) {
    p <- ggplot() +
        annotate("text", x = 0, y = 0, label = "No anchors") +
        labs(title = target_name) +
        theme_void()
} else {
    # Ensure numeric
    dt[, referenceStart := as.numeric(referenceStart)]
    dt[, referenceEnd   := as.numeric(referenceEnd)]
    dt[, queryStart     := as.numeric(queryStart)]
    dt[, queryEnd       := as.numeric(queryEnd)]

    # Scaffold-level assemblies would otherwise produce thousands of facets
    max_chroms <- 30
    top_ref   <- dt[, .N, by = referenceChromosome][order(-N)][seq_len(min(.N, max_chroms)), referenceChromosome]
    top_query <- dt[, .N, by = queryChromosome][order(-N)][seq_len(min(.N, max_chroms)), queryChromosome]
    dt <- dt[referenceChromosome %in% top_ref & queryChromosome %in% top_query]

    dt[, referenceChromosome := factor(referenceChromosome, levels = natural_sort(top_ref))]
    dt[, queryChromosome     := factor(queryChromosome,     levels = rev(natural_sort(top_query)))]

    # Midpoints for plotting
    dt[, ref_mid   := (referenceStart + referenceEnd) / 2]
    dt[, query_mid := (queryStart + queryEnd) / 2]

    p <- ggplot(dt, aes(x = ref_mid, y = query_mid, colour = strand)) +
        geom_point(size = 0.3, alpha = 0.6) +
        facet_grid(queryChromosome ~ referenceChromosome, scales = "free", space = "free") +
        scale_colour_manual(values = c("+" = "#2166ac", "-" = "#b2182b"),
                            na.value = "grey50") +
        labs(x = "Reference position", y = "Target position",
             title = target_name,
             subtitle = sprintf("%d anchors", nrow(dt))) +
        theme_minimal(base_size = 8) +
        theme(
            strip.text = element_text(size = 5),
            panel.grid.minor = element_blank(),
            axis.text = element_blank(),
            axis.ticks = element_blank()
        )
}

ggsave(out_file,     p, width = plot_width, height = plot_height, dpi = plot_dpi, bg = "white")
ggsave(preview_file, p, width = plot_width, height = plot_height, dpi = preview_dpi, bg = "white")

sink(type = "message")
sink(type = "output")
