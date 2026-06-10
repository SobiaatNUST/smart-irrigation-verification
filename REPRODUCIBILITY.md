# Reproducibility guide & traceability matrix

This document maps **every table, figure, and headline number in the
paper** to the repository artefact that produces it, and states whether
it is fully reproducible, regenerated on demand, or derived. It is the
authoritative companion to `README.md`.

Status legend:

- **COMMITTED** — backing data is in the repo; the value can be read/checked directly.
- **REGENERATE** — script is provided; raw data is *not* committed (size) and must be re-run.
- **DERIVED** — assembled from other committed raws; no separate data file.
- **MANUAL** — definitional/diagrammatic content (no experiment); drawn in LaTeX/TikZ.

> **Figure workflow caveat.** No script emits a paper figure as an
> image. Every figure is a LaTeX/TikZ/pgfplots block populated by hand
> from the parsed CSV/`.txt` numbers. "Reproducible" for a figure means
> the *underlying numbers* can be regenerated; transcription into TikZ
> is a manual camera-ready step. `analyze_mo3_grid.py` is the sole
> figure-support script.

---

## Traceability matrix

| Paper item | What it shows | Repository location | Script to (re)generate | Status |
|---|---|---|---|---|
| **Table: related work** (`tab:relwork`) | Qualitative comparison | — | — | MANUAL |
| **Table: ET error dist.** (`tab:eta`) | Calibrated ET error | `models/M3/M3_mdp_synthesis.pm` (constants) | — | MANUAL (calibration) |
| **Table: M2 zones** (`tab:m2zones`) | Five-zone thresholds | `models/M2/M2_threshold_zones.pm` | — | MANUAL (definition) |
| **Table: factorial design** (`tab:config`) | Scenario grid | `scripts/*` (sweep loops) | — | MANUAL |
| **Table: M1 vs M2** (`tab:det`) | Baseline verification | `results/deterministic/M1_parsed.csv`, `M2_parsed.csv` | `M1_run.sh`, `M2_run.sh` | **COMMITTED** |
| **Table: M3 named policies** (`tab:pareto`) | σ*₀.₉₀/σ*₀.₉₅/σ*≤₄₀ | `results/mo1/tier1_named_policies.csv` (+ raw txts) | `run_mo1_tier1_named.sh` | **COMMITTED** |
| **Table: MO2 budget frontier** (`tab:budget_pareto`) | Safety vs budget B | `results/mo2/budget_sweep.csv` + `budget_sweep_raw.zip`, `budget_sweep_more_raw.zip` | `run_mo2_budget_sweep.sh 0.025` | **COMMITTED** |
| **Table: sensitivity** (`tab:sens`) | x(0) sensitivity | `results/sensitivity/sensitivity.csv` (+ M1/M2 from `deterministic/`) | `run_sensitivity.sh` | **COMMITTED** |
| **Table: scheduler points** (`tab:moschedulers`) | Deployable scheduler operating points | `results/scheduler_exports/MO1,MO2/*.pareto.txt`, `*.pareto_summary.json` | `scheduler_exports/run_sched_export_mo*.sh` | **COMMITTED** (raw `.scheduler`/`.states` off-repo) |
| **Fig: architecture** (`fig:arch`) | System diagram | — | — | MANUAL |
| **Fig: dependency DAG** (`fig:dag`) | Within-step deps | — | — | MANUAL |
| **Fig: M3 named heatmaps** (`fig:m3namedheat`) | Water/safety per scenario | `results/mo1/tier1_named_policies.csv` | `run_mo1_tier1_named.sh` | **COMMITTED** (+manual TikZ) |
| **Fig: operating points** (`fig:m3pareto`) | Water–safety plane | `results/mo1/tier1_named_policies.csv` + `results/mo1/theta_sweep/` | `run_mo1_tier1_named.sh` + `run_mo1_theta_sweep.sh` | **COMMITTED** |
| **Fig: θ-axis Pareto** (`fig:pareto`) | Frontier vs θ | `results/mo1/theta_sweep/theta_sweep.csv` + raw zips | `run_mo1_theta_sweep.sh 0.025` | **COMMITTED** |
| **Fig: budget Pareto** (`fig:budget_pareto`) | Frontier vs B | `results/mo2/budget_sweep.csv` + raw zips | `run_mo2_budget_sweep.sh` | **COMMITTED** |
| **Fig: MO3 feasibility** (`fig:mo3feas`) | Residual-violation tiles | `results/mo3/mo3_results_B25.csv`, `mo3_results_B20_B30.csv`, `mo3_results_raw.zip` | `run_mo3_grid.sh` → `analyze_mo3_grid.py` | **COMMITTED** |
| **Fig: MO4 heatmap** (`fig:mo4heat`) | Water cost vs V | `results/mo4/mo4_results_V0.05.csv`, `mo4_results_V0.5_1.0.csv`, `mo4_results_raw.zip` | `run_mo4_grid.sh` | **COMMITTED** |
| **Fig: MO1/MO2 frontier** (`fig:mo_pareto_a`) | Water vs P(unsafe) | `results/mo1/` + `results/mo2/` | `run_mo1_*` (+`run_mo2_budget_sweep.sh`) | **COMMITTED** |
| **Fig: MO3/MO4 frontier** (`fig:mo_pareto_b`) | Water vs E[viol] | `results/mo3/` + `results/mo4/` | `run_mo3_grid.sh` (+`run_mo4_grid.sh`) | **COMMITTED** |
| **Fig: policy slices** (`fig:policyheatmaps`) | u(x, w) lookup | `figures/policy_heatmaps.pdf` (+ `analysis/analysis_scripts/plot_policy_heatmaps.py`) | `run_sched_export_mo*.sh` → `plot_policy_heatmaps.py` | **COMMITTED** (rendered figure + generator) |
| **Headline: 43–66 % water saving** | M3 vs M2 | `results/mo1/tier1_named_policies.csv` vs `results/deterministic/M2_parsed.csv` | as above | **COMMITTED** |

---

## End-to-end workflow

```
PRISM model (.pm)  --sed/-const-->  per-scenario temp model
        |                                   |
        |                                   v
        |                          Storm (sparse, multi-obj)
        |                                   |
        |                                   v
        |                          raw .txt console output
        |                                   |
        |          parse_storm_output.py    v
        |               ---------->   tidy CSV  ---->  numbers in paper tables
        |                                                       |
        |                                   analyze_mo3_grid.py |
        +-----------------------------------------> (manual)  TikZ figure
```

1. **Set `STORM_BIN`** in each script (or pass `--storm`).
2. **Run** the relevant driver (see `README.md` §4); scenarios are
   produced by `sed`/`-const` substitution into the base `.pm`.
3. **Parse** raw `.txt` with `scripts/utilities/parse_storm_output.py`.
4. **Analyse** MO3 with `analysis/analysis_scripts/analyze_mo3_grid.py`.
5. **Transcribe** the parsed numbers into the paper's TikZ blocks
   (manual; the only undocumented-by-tooling step).

## Hidden assumptions / manual steps

- Storm binary must be built with multi-objective support; the sparse
  engine is assumed.
- Horizon is `C<=140` (28 steps × 5), soil `x∈[0..100] mm`, threshold
  `x_min = 30 mm` (the policy-slice figure caption uses `25 mm`, which is
  specific to that figure's colour scale).
- The legacy `phi_mo4` / `mo4_*` tags inside `results/mo3/` denote the
  **paper's MO3** query (min violations under water budget) — see the
  mapping table in `README.md` §1.
- MO1 named-policy runs are long (hours per cell); use `--parallel`.
