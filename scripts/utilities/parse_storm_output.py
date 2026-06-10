"""Parse Storm console outputs into a tidy CSV.

Walks a directory of Storm `.txt` files emitted by the experiment scripts
in ../, extracts numeric result and timing statistics, and writes a single
CSV. Used to assemble the named-policy and grid-sweep summaries reported
in the paper.

Usage:
    python parse_storm_output.py <input_dir> <output.csv>

Example:
    python parse_storm_output.py \\
        ../../results/mo1/Results_T1_Named_Policies \\
        ../../results/mo1/tier1_named_policies.csv
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

RESULT_RE = re.compile(r"^Result \(for initial states\):\s+(\S+)", re.MULTILINE)
STATES_RE = re.compile(r"^States:\s+(\d+)", re.MULTILINE)
TRANS_RE  = re.compile(r"^Transitions:\s+(\d+)", re.MULTILINE)
BUILD_RE  = re.compile(r"Time for model construction:\s+([\d.]+)s", re.MULTILINE)
CHECK_RE  = re.compile(r"Time for model checking:\s+([\d.]+)s", re.MULTILINE)


def parse_one(path: Path) -> dict | None:
    text = path.read_text(errors="ignore")
    m = RESULT_RE.search(text)
    if not m:
        return None
    return {
        "file":         path.name,
        "result":       m.group(1),
        "states":       (STATES_RE.search(text) or [None, ""]).group(1),
        "transitions":  (TRANS_RE.search(text)  or [None, ""]).group(1),
        "build_sec":    (BUILD_RE.search(text)  or [None, ""]).group(1),
        "check_sec":    (CHECK_RE.search(text)  or [None, ""]).group(1),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_dir", type=Path)
    ap.add_argument("output_csv", type=Path)
    args = ap.parse_args()

    rows = []
    for p in sorted(args.input_dir.glob("*.txt")):
        r = parse_one(p)
        if r is not None:
            rows.append(r)

    if not rows:
        raise SystemExit(f"No parseable Storm output found in {args.input_dir}")

    args.output_csv.parent.mkdir(parents=True, exist_ok=True)
    with args.output_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print(f"Wrote {len(rows)} rows to {args.output_csv}")


if __name__ == "__main__":
    main()
