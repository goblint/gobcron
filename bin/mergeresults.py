#! /usr/bin/env python3

import argparse
import sys
from pathlib import Path

import pandas as pd

parser = argparse.ArgumentParser(
    description="Join the verdict/result columns of each results/*/finalscores.csv into a single Excel file."
)
parser.add_argument("--outdir", default="results", help="Directory containing the per-run result folders (default: results)")
parser.add_argument("--out", default="combined_verdicts.xlsx", help="Output Excel file name, relative to --outdir (default: combined_verdicts.xlsx)")
parser.add_argument("-t", "--use-tags", action="store_true", help="Label columns using each folder's 'tag' file instead of the folder name (errors on duplicate tags)")
args = parser.parse_args()

KEY = ["ymlfile", "property"]

outdir = Path(args.outdir)
csv_files = sorted(
    p for p in outdir.glob("*/finalscores.csv")
    if not any(tok in p.parent.name for tok in (".~lock", "~"))
)

if len(csv_files) < 2:
    sys.exit(f"Error: expected at least 2 finalscores.csv under {outdir}/*/ , found {len(csv_files)}")

prefixes = []
if args.use_tags:
    for p in csv_files:
        tagfile = p.parent / "tag"
        tag = tagfile.read_text().strip() if tagfile.is_file() else p.parent.name
        prefixes.append(tag)
    collisions = {t for t in prefixes if prefixes.count(t) > 1}
    if collisions:
        detail = ", ".join(f"'{t}'" for t in sorted(collisions))
        sys.exit(f"Error: --use-tags produced duplicate labels ({detail}). Rename tags or omit --use-tags.")
else:
    prefixes = [p.parent.name for p in csv_files]

merged = None
for p, prefix in zip(csv_files, prefixes):
    cols = KEY + (["expected", "verdict", "result"] if merged is None else ["verdict", "result"])
    df = pd.read_csv(p, usecols=cols)
    df = df.rename(columns={"verdict": f"{prefix}_verdict", "result": f"{prefix}_result"})
    if merged is None:
        merged = df
    else:
        merged = merged.merge(df, on=KEY, how="outer")

outpath = outdir / args.out
merged.to_excel(outpath, index=False, engine="openpyxl")

ncols = 2 * len(csv_files) + len(KEY) + 1
print(f"Joined {len(csv_files)} folders: " + ", ".join(f"{p.parent.name} -> '{pr}'" for p, pr in zip(csv_files, prefixes)))
print(f"Rows: {len(merged)}, columns: {ncols}")
print(f"Wrote {outpath}")
