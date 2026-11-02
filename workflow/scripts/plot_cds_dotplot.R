# plot_cds_dotplot.R — Dotplot of reference CDS hits: position in reference vs position in target
# Called by Snakemake: snakemake@input, snakemake@output, snakemake@params, snakemake@log
#
# Each point is one reference CDS, placed at its primary minimap2 hit in the reference (x)
# and in the target (y).  Use it before AnchorWave to choose a mode: a clean diagonal per
# chromosome (inversions allowed) suits genoAli; off-diagonal blocks (translocations) or
# repeated blocks (duplications / ploidy differences) call for proali.
#
# Writes the full-resolution plot and a low-resolution preview for the QC HTML report.

log_con <- file(snakemake@log[[1]], open = "wt")
sink(log_con, type = "message")
sink(log_con, type = "output")

library(data.table)
library(ggplot2)

ref_sam      <- snakemake@input[["ref_sam"]]
target_sam   <- snakemake@input[["target_sam"]]
out_file     <- snakemake@output[["plot"]]
preview_file <- snakemake@output[["preview"]]
target_name  <- snakemake@wildcards[["target"]]
min_mapq     <- as.integer(snakemake@params[["min_mapq"]])

plot_width  <- 14
plot_height <- 12
plot_dpi    <- 300
preview_dpi <- 72

# Primary, mapped alignments only (-F 0x904 drops unmapped, secondary, supplementary).
# SAM rows have a variable number of tag columns, so cut to the fixed fields first.
read_hits <- function(sam) {
    cmd <- sprintf("samtools view -F 0x904 -q %d %s | cut -f1-4", min_mapq, shQuote(sam))
    dt <- fread(cmd = cmd, header = FALSE, sep = "\t",
                col.names = c("cds", "flag", "chrom", "pos"),
                colClasses = c("character", "integer", "character", "numeric"))
    dt[, reverse := bitwAnd(flag, 16L) > 0]
    dt[, flag := NULL]
    dt
}

# Natural sort: chr1, chr2, ..., chr10, then scaf_1, scaf_2, ... (FASTAs are often sorted lexically)
natural_sort <- function(x) {
    prefix <- sub("[0-9].*$", "", x)
    num    <- suppressWarnings(as.numeric(sub("^[^0-9]*([0-9]+).*$", "\\1", x)))
    x[order(prefix, num, x, method = "radix")]
}

ref    <- read_hits(ref_sam)
target <- read_hits(target_sam)
message(sprintf("Primary hits (MAPQ >= %d): reference %d, target %d",
                min_mapq, nrow(ref), nrow(target)))

dt <- merge(ref, target, by = "cds", suffixes = c("_ref", "_target"))
message(sprintf("CDS with a hit in both genomes: %d", nrow(dt)))

if (nrow(dt) == 0) {
    p <- ggplot() +
        annotate("text", x = 0, y = 0, label = "No CDS with a hit in both genomes") +
        labs(title = target_name) +
        theme_void()
} else {
    dt[, strand := ifelse(reverse_ref == reverse_target, "+", "-")]

    # Scaffold-level assemblies would otherwise produce thousands of facets
    max_chroms <- 30
    top_ref    <- dt[, .N, by = chrom_ref][order(-N)][seq_len(min(.N, max_chroms)), chrom_ref]
    top_target <- dt[, .N, by = chrom_target][order(-N)][seq_len(min(.N, max_chroms)), chrom_target]
    dt <- dt[chrom_ref %in% top_ref & chrom_target %in% top_target]

    dt[, chrom_ref    := factor(chrom_ref,    levels = natural_sort(top_ref))]
    dt[, chrom_target := factor(chrom_target, levels = rev(natural_sort(top_target)))]

    p <- ggplot(dt, aes(x = pos_ref, y = pos_target, colour = strand)) +
        geom_point(size = 0.3, alpha = 0.6) +
        facet_grid(chrom_target ~ chrom_ref, scales = "free", space = "free", switch = "both") +
        scale_colour_manual(values = c("+" = "#2166ac", "-" = "#b2182b")) +
        labs(x = "Reference position", y = "Target position",
             title = target_name,
             subtitle = sprintf("%d reference CDS, primary hits, MAPQ >= %d", nrow(dt), min_mapq)) +
        theme_minimal(base_size = 8) +
        theme(
            strip.text = element_text(size = 5),
            strip.text.y.left = element_text(angle = 0),
            panel.grid.minor = element_blank(),
            panel.border = element_rect(colour = "grey80", fill = NA, linewidth = 0.2),
            panel.spacing = unit(0, "pt"),
            axis.text = element_blank(),
            axis.ticks = element_blank()
        )
}

ggsave(out_file,     p, width = plot_width, height = plot_height, dpi = plot_dpi, bg = "white")
ggsave(preview_file, p, width = plot_width, height = plot_height, dpi = preview_dpi, bg = "white")

sink(type = "message")
sink(type = "output")
