import pandas as pd
from pathlib import Path
from snakemake.utils import validate


# ── Load and validate config ────────────────────────────────────────────────
validate(config, schema="../schemas/config.schema.yaml")

OUTDIR = config.get("outdir", "results")
REF_NAME = config["reference"]["name"]
REF_FASTA = config["reference"]["fasta"]
REF_GFF = config["reference"]["gff"]


# ── Load and validate sample sheet ──────────────────────────────────────────
def load_targets(sheet_path):
    """Read the targets TSV, validate, and return a DataFrame indexed by sample."""
    df = pd.read_csv(sheet_path, sep="\t", dtype=str, comment="#")
    df.columns = df.columns.str.strip()
    validate(df, schema="../schemas/targets.schema.yaml")
    # Fill defaults
    df["mode"] = df["mode"].fillna("genoAli")
    df["extra"] = df["extra"].fillna("")
    df = df.set_index("sample", drop=False)
    # Sanity checks
    assert df.index.is_unique, "Duplicate sample names in targets sheet"
    assert REF_NAME not in df.index, (
        f"Target sample '{REF_NAME}' has the same name as the reference"
    )
    for _, row in df.iterrows():
        if row["mode"] == "proali":
            assert pd.notna(row.get("proali_R")) and row.get("proali_R", "") != "", (
                f"proali_R required for proali target '{row['sample']}'"
            )
            assert pd.notna(row.get("proali_Q")) and row.get("proali_Q", "") != "", (
                f"proali_Q required for proali target '{row['sample']}'"
            )
    return df


TARGETS = load_targets(config["targets"])
TARGET_NAMES = list(TARGETS.index)
# All genome names: reference + targets (used for stage_fasta, faidx, minimap2)
ALL_GENOMES = [REF_NAME] + TARGET_NAMES


# ── Input helpers ───────────────────────────────────────────────────────────
def genome_source_fasta(wildcards):
    """Return the original FASTA path for a genome (reference or target)."""
    if wildcards.genome == REF_NAME:
        return REF_FASTA
    return TARGETS.loc[wildcards.genome, "fasta"]


def staged_fasta(genome):
    """Path to the staged (decompressed, header-trimmed) FASTA."""
    return f"{OUTDIR}/genomes/{genome}.fa"


def staged_fai(genome):
    """Path to the .fai index of a staged FASTA."""
    return f"{OUTDIR}/genomes/{genome}.fa.fai"


# ── Resource helper ─────────────────────────────────────────────────────────
def res(rule_name, key, default=None):
    """Look up a resource value from config['resources'][rule][key], with a default."""
    return config.get("resources", {}).get(rule_name, {}).get(key, default)
