"""MO3 residual-violation map: aggregation and elasticity analysis.

Paper convention (eq. 16): phi_mo3 minimises expected unsafe ticks under
a water budget B. Reads Storm CSV outputs from ../../results/mo3/
and produces the 9-cell soil x weather x budget grid used in
Table V (tab:mo3grid) and Fig. 8 (fig:mo3grid) of the paper.

The CSV scenario tags are named `phi_mo4` / `mo4_*` because the
development tree predated the paper's MO renumbering; the semantic
content matches the paper's phi_mo3.

Soil mapping (per models/M3/M3_mdp_synthesis.pm calibration):
    c = 0.01   -> Clay        (low drainage)
    c = 0.025  -> Loam        (medium)
    c = 0.05   -> Sandy loam  (high drainage)
"""

import re
from pathlib import Path

# The Storm CSV embeds un-escaped double quotes inside the `property`
# column (e.g. R{"safety_violations"}...), which breaks csv.DictReader.
# We pull the columns we need with a regex on the scenario tag instead.
ROW_RE = re.compile(
    r"^phi_mo4,mo4_c(?P<c>[\d.]+)_w(?P<w>\d)_x40_Rw(?P<Rw>\d+),"
    r"(?P<cc>[\d.]+),\d,(?P<wname>Dry|Moderate|Wet),40,(?P<Rwc>\d+),"
    r'.*?\)",(?P<viol>[\d.eE+-]+),'
)

SOIL_NAME = {0.01: "Clay", 0.025: "Loam", 0.05: "Sandy loam"}
WEATHER_ORDER = {"Dry": 0, "Moderate": 1, "Wet": 2}
BUDGETS = (20, 25, 30)
FEAS_TOL = 1e-6  # treat results below this as certified-feasible (0)


def load(csv_paths):
    rows = []
    for p in csv_paths:
        for line in Path(p).read_text().splitlines():
            m = ROW_RE.match(line)
            if not m:
                continue
            rows.append(
                {
                    "c": float(m["cc"]),
                    "w_name": m["wname"],
                    "Rw": int(m["Rwc"]),
                    "viol": float(m["viol"]),
                }
            )
    return rows


def grid(rows):
    g = {}
    for r in rows:
        g[(SOIL_NAME[r["c"]], r["w_name"], r["Rw"])] = r["viol"]
    return g


def main():
    here = Path(__file__).resolve().parents[2] / "results" / "mo3"
    rows = load([here / "mo3_results_B25.csv",
                 here / "mo3_results_B20_B30.csv"])
    g = grid(rows)

    print("Soil       Weather   B=20    B=25    B=30")
    for soil in ("Clay", "Loam", "Sandy loam"):
        for weather in sorted(WEATHER_ORDER, key=WEATHER_ORDER.get):
            vals = [g[(soil, weather, B)] for B in BUDGETS]
            cells = ["0_dag" if v <= FEAS_TOL else f"{v:.3f}" for v in vals]
            print(f"{soil:<10} {weather:<8} {cells[0]:>7} {cells[1]:>7} {cells[2]:>7}")

    print()
    for B in BUDGETS:
        total = sum(v for (s, w, b), v in g.items() if b == B)
        feas = sum(1 for (s, w, b), v in g.items() if b == B and v <= FEAS_TOL)
        print(f"B={B}: sum={total:.3f}  feasible cells={feas}/9")

    print()
    print("Sandy-loam elasticity (unsafe ticks per mm, B in [20,30]):")
    for weather in ("Dry", "Moderate", "Wet"):
        v20 = g[("Sandy loam", weather, 20)]
        v30 = g[("Sandy loam", weather, 30)]
        print(f"  {weather:<8} slope = {(v20 - v30) / 10:.3f}/mm")


if __name__ == "__main__":
    main()
