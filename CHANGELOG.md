# Changelog

All notable changes to this reproducibility artefact are documented here.

## [Unreleased] — scheduler-export completion pass

### Added (recovered from `M3_Policy_Synthesis_MAC_Results`, Storm 1.13.0)
- **Scheduler operating points / metadata** → `results/scheduler_exports/`
  (`MO1/`, `MO2/`, `G3_reference/`): weighted-sum sweep logs
  (`*.pareto.txt`, `*.pareto_summary.json`), named-policy synthesis
  results (`*.txt`, `*.props`), and the deployable σ*₀.₉₅ summary
  (`g3_loam_dry_x40_safe95.summary.json`: water 30.24 mm, P(unsafe)=0).
  Backs **`tab:moschedulers`**.
- **`figures/policy_heatmaps.pdf`** — the rendered 4-panel policy-slice
  figure, i.e. **`fig:policyheatmaps`** (previously a placeholder box in
  the manuscript).
- **`analysis/analysis_scripts/plot_policy_heatmaps.py`** — generator
  that builds the figure from the `.scheduler` files.
- **`analysis/MO_PARETO_ANALYSIS.md`** — Pareto/scheduler analysis notes.

### Changed
- `scheduler_exports` row flipped **REGENERATE → COMMITTED** for the
  operating-point results and the policy figure; README/REPRODUCIBILITY
  updated. Confirmed `x_min = 25 mm` is the correct marker for
  `fig:policyheatmaps` (the generator draws the threshold line at 25).

### Still not committed (size, not availability)
- Raw lookup tables `*.scheduler` (~158 MB each) and `g3_*.states`
  (~1.3 GB) exceed GitHub limits — regenerate via the scripts.

## [Unreleased] — data-completion pass

### Added (missing result sets recovered from the working tree)
- **MO1 θ-sweep** → `results/mo1/theta_sweep/` — `theta_sweep.csv`
  (loam reference, θ ∈ {0.60…0.99}) + `theta_sweep_raw.zip` +
  `theta_sweep_ext_raw.zip` (Moderate/Wet). Backs `fig:pareto`,
  `fig:m3pareto`.
- **MO2 budget sweep** → `results/mo2/` — `budget_sweep.csv` (11 cells,
  parsed) + `budget_sweep_raw.zip` (loam B20–60) +
  `budget_sweep_more_raw.zip` (clay/sandy B20–40). Backs
  `tab:budget_pareto`, `fig:budget_pareto`.
- **MO4 grid** → `results/mo4/` — `mo4_results_V0.05.csv` (9 cells,
  full metadata) + `mo4_results_V0.5_1.0.csv` (18 cells, re-parsed from
  raws whose summary CSV was previously all-N/A) + `mo4_results_raw.zip`
  (27 raws). Backs `fig:mo4heat`, `fig:mo_pareto_b`.
- **Sensitivity** → `results/sensitivity/sensitivity.csv`. Backs `tab:sens`.
- **`scripts/run_sensitivity.sh`** — sensitivity driver (path-fixed to
  `../models/M3/M3_mdp_synthesis.pm`); the repo previously had no
  sensitivity script.

### Changed
- `README.md`, `REPRODUCIBILITY.md`, and the per-folder READMEs
  (`mo2`, `mo4`, `sensitivity`, new `mo1/theta_sweep`) updated: those
  rows flipped **REGENERATE/DERIVED → COMMITTED**. Documented the
  legacy↔paper MO-numbering shift (repo `mo2` ← G1 budget sweep;
  `mo4` ← legacy `phi_mo2`; `mo3` ← legacy `phi_mo4`).

### Still not committed
- **Scheduler-export lookup tables** — the only remaining gap; the
  `.scheduler`/`.states`/`.result` outputs were never archived in the
  working tree. Scripts are present; regenerate with Storm.

## [Unreleased] — repository readiness pass

### Fixed
- **Script ↔ file path mismatch (critical).** All 13 driver scripts
  referenced the original working-directory filenames
  (`openloop_irrigation_v3.pm`, `M2_ThresholdBased_Uncertainty_V3.pm`,
  `M3_MDP_Synthesis_V3.pm`, `ThresholdBased_V3.pctl`,
  `openloop_v3.props`) that do **not** exist in the repository. Updated
  the `MODEL_FILE` / `PROPERTY_FILE` defaults to the in-repo paths so
  the scripts run from a fresh clone without renaming:
  - `scripts/M1_run.sh` → `../models/M1/M1_openloop.pm`, `../properties/single_objective/M1_properties.props`
  - `scripts/M2_run.sh` → `../models/M2/M2_threshold_zones.pm`, `../properties/single_objective/M2_properties.pctl`
  - `scripts/run_mo1_tier1_named.sh`, `run_mo1_theta_sweep.sh`, `run_mo2_budget_sweep.sh`, `run_mo3_grid.sh`, `run_mo4_grid.sh` → `../models/M3/M3_mdp_synthesis.pm`
  - `scripts/scheduler_exports/run_sched_export_mo{1..4}.sh` → `../../models/M3/M3_mdp_synthesis.pm`

### Changed
- **README.md** rewritten: corrected Storm version (1.13.0 reference,
  ≥1.9 supported; was 1.9.0), added the MO1–MO4 ↔ legacy-tag mapping,
  corrected table/figure label references to the paper's actual labels,
  added an honest per-folder data-availability status, and added
  install / license / citation / figure-generation sections.

### Added
- **REPRODUCIBILITY.md** — full paper-item → script → data traceability
  matrix, end-to-end workflow diagram, and the list of manual steps /
  hidden assumptions.
- **CITATION.cff** — machine-readable citation metadata.
- **requirements.txt** — documents the stdlib-only Python footprint and
  the external tool versions.
- **CHANGELOG.md** — this file.

### Known remaining gaps (require author action — not auto-fixable)
- `results/mo2/`, `results/mo4/`, `results/scheduler_exports/`, and the
  MO1 θ-sweep contain only README placeholders; the backing raw/parsed
  data is not committed. The paper reports MO2, MO4, and scheduler
  results, so either commit these outputs or keep them as REGENERATE.
- Repository URL set to
  `github.com/SobiaatNUST/smart-irrigation-verification` in
  `CITATION.cff` and the paper's `sis_artefacts_repo` citation.
- Storm version reported here (1.13.0) should match the manuscript and
  the version actually used to generate the committed CSVs.
- No automated figure-plotting scripts: figures are transcribed into
  TikZ by hand from the parsed CSVs.
