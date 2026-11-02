def _anchorwave_cmd(wildcards):
    """Build the anchorwave command string based on the target's mode."""
    row = TARGETS.loc[wildcards.target]
    mode = row["mode"]

    if mode == "genoAli":
        inv_flag = "-IV" if config.get("genoali", {}).get("inversions", True) else ""
        global_extra = config.get("genoali", {}).get("extra", "")
        cmd = f"anchorwave genoAli {inv_flag} {global_extra}"
    elif mode == "proali":
        R = row["proali_R"]
        Q = row["proali_Q"]
        global_extra = config.get("proali", {}).get("extra", "")
        cmd = f"anchorwave proali -R {R} -Q {Q} {global_extra}"
    else:
        raise ValueError(f"Unknown mode '{mode}' for target '{wildcards.target}'")

    per_target_extra = row.get("extra", "") or ""
    return f"{cmd} {per_target_extra}".strip()


rule anchorwave_align:
    """Run AnchorWave genoAli or proali for one target against the reference."""
    input:
        ref_fasta=staged_fasta(REF_NAME),
        target_fasta=lambda wc: staged_fasta(wc.target),
        gff=staged_gff(),
        cds=f"{OUTDIR}/reference/cds.fa",
        ref_sam=f"{OUTDIR}/sam/{REF_NAME}.sam",
        target_sam=lambda wc: f"{OUTDIR}/sam/{wc.target}.sam",
    output:
        maf=f"{OUTDIR}/align/{{target}}/{{target}}.maf",
        fmaf=f"{OUTDIR}/align/{{target}}/{{target}}.f.maf",
        anchors=f"{OUTDIR}/align/{{target}}/{{target}}.anchors",
    log:
        log=f"logs/anchorwave_align/{{target}}.log",
        time=f"logs/anchorwave_align/{{target}}.time",
    params:
        cmd=_anchorwave_cmd,
    threads: res("anchorwave_align", "threads", 16)
    resources:
        mem_mb=res("anchorwave_align", "mem_mb", 253952),
        runtime=res("anchorwave_align", "runtime", 4320),
    wildcard_constraints:
        target="|".join(TARGET_NAMES),
    shell:
        r"""
        /usr/bin/time -v -o {log.time} \
        {params.cmd} \
            -i {input.gff} \
            -as {input.cds} \
            -r {input.ref_fasta} \
            -a {input.target_sam} \
            -ar {input.ref_sam} \
            -s {input.target_fasta} \
            -n {output.anchors} \
            -o {output.maf} \
            -f {output.fmaf} \
            -t {threads} \
        &> {log.log}
        """
