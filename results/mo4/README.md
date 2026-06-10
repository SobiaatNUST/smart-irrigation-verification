# results/mo4 — MO4: minimum water under a violation budget

Paper query **MO4**: `multi(R{"water_usage"}min=? [C<=140], R{"safety_violations"}<=V [C<=140])`
(minimise expected water subject to an expected-violation budget `V`).
Backs **Fig. `fig:mo4heat`** and the MO3/MO4 frontier
**Fig. `fig:mo_pareto_b`**.

> Note: in the original working tree these runs were tagged `phi_mo2`
> / `mo2_*`; they correspond to the paper's **MO4** (not MO2). See the
> mapping table in the top-level `README.md`.

## Files (now committed)
- `mo4_results_V0.05.csv` — full-metadata grid at `V = 0.05`
  (9 cells: 3 soils × 3 weather, `x(0)=40`), columns include
  `c, w_name, Rv_cap, property, result_water_min, states, …`.
- `mo4_results_V0.5_1.0.csv` — `V ∈ {0.5, 1.0}` (18 cells), parsed
  with `parse_storm_output.py` (scenario encoded in the `file` name
  `mo2_c<c>_w<w>_x40_Rv<V>.txt`).
- `mo4_results_raw.zip` — all 27 raw Storm `.txt` outputs.

All 27 cells carry numeric results (e.g. clay/Dry: 25.21 / 23.04 /
21.39 mm at V = 0.05 / 0.5 / 1.0).

## Regenerate
```bash
bash ../../scripts/run_mo4_grid.sh --storm /path/to/storm
python ../../scripts/utilities/parse_storm_output.py <raw_dir> mo4_results.csv
```
