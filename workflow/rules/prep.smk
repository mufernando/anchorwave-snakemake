# ── Stage FASTA: decompress .gz + trim headers to first word ────────────────
rule stage_fasta:
    """Decompress (if .gz) and trim FASTA headers to the first whitespace-delimited word."""
    input:
        fasta=genome_source_fasta,
    output:
        fasta=f"{OUTDIR}/genomes/{{genome}}.fa",
    log:
        f"logs/stage_fasta/{{genome}}.log",
    threads: res("stage_fasta", "threads", 1)
    resources:
        mem_mb=res("stage_fasta", "mem_mb", 4096),
        runtime=res("stage_fasta", "runtime", 60),
    wildcard_constraints:
        genome="|".join(ALL_GENOMES),
    shell:
        r"""
        (
        if [[ "{input.fasta}" == *.gz ]]; then
            gunzip -c {input.fasta}
        else
            cat {input.fasta}
        fi \
        | awk '/^>/{{ print $1; next }}{{ print }}' \
        > {output.fasta}
        ) &> {log}
        """


# ── samtools faidx ──────────────────────────────────────────────────────────
rule faidx:
    input:
        fasta=f"{OUTDIR}/genomes/{{genome}}.fa",
    output:
        fai=f"{OUTDIR}/genomes/{{genome}}.fa.fai",
    log:
        f"logs/faidx/{{genome}}.log",
    threads: res("faidx", "threads", 1)
    resources:
        mem_mb=res("faidx", "mem_mb", 2048),
        runtime=res("faidx", "runtime", 30),
    wildcard_constraints:
        genome="|".join(ALL_GENOMES),
    shell:
        "samtools faidx {input.fasta} &> {log}"


# ── Stage GFF: decompress .gz reference annotation ─────────────────────────
rule stage_gff:
    """Decompress the reference GFF3 (if .gz); AnchorWave only reads plain text."""
    input:
        gff=REF_GFF,
    output:
        gff=staged_gff(),
    log:
        "logs/stage_gff.log",
    threads: res("stage_gff", "threads", 1)
    resources:
        mem_mb=res("stage_gff", "mem_mb", 2048),
        runtime=res("stage_gff", "runtime", 30),
    shell:
        r"""
        (
        if [[ "{input.gff}" == *.gz ]]; then
            gunzip -c {input.gff}
        else
            cat {input.gff}
        fi \
        > {output.gff}
        ) &> {log}
        """


# ── AnchorWave gff2seq: extract reference CDS sequences ────────────────────
rule gff2seq:
    """Extract CDS sequences from the reference using the GFF annotation."""
    input:
        fasta=staged_fasta(REF_NAME),
        gff=staged_gff(),
    output:
        cds=f"{OUTDIR}/reference/cds.fa",
    log:
        "logs/gff2seq.log",
    params:
        extra=config.get("gff2seq", {}).get("extra", ""),
    threads: res("gff2seq", "threads", 1)
    resources:
        mem_mb=res("gff2seq", "mem_mb", 8192),
        runtime=res("gff2seq", "runtime", 60),
    shell:
        """
        anchorwave gff2seq \
            -r {input.fasta} \
            -i {input.gff} \
            -o {output.cds} \
            {params.extra} \
        &> {log}
        """


# ── minimap2: map CDS to each genome ───────────────────────────────────────
rule minimap2_cds:
    """Map reference CDS sequences to a genome with minimap2 (splice mode)."""
    input:
        genome=f"{OUTDIR}/genomes/{{genome}}.fa",
        cds=f"{OUTDIR}/reference/cds.fa",
    output:
        sam=f"{OUTDIR}/sam/{{genome}}.sam",
    log:
        f"logs/minimap2_cds/{{genome}}.log",
    params:
        args=config.get("minimap2", {}).get("args", "-x splice -k 12 -a -p 0.4 -N 20"),
    threads: res("minimap2_cds", "threads", 8)
    resources:
        mem_mb=res("minimap2_cds", "mem_mb", 32768),
        runtime=res("minimap2_cds", "runtime", 360),
    wildcard_constraints:
        genome="|".join(ALL_GENOMES),
    shell:
        """
        minimap2 {params.args} \
            -t {threads} \
            {input.genome} {input.cds} \
            > {output.sam} \
        2> {log}
        """
