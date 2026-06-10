# results/mo2 — MO2: maximum safety under a water budget

Paper query **MO2**: `multi(Pmax=? [G "safe"], R{"water_usage"}<=B [C<=140])`
(maximise certified safety probability subject to a cumulative water
budget `B` mm). Backs **Table `tab:budget_pareto`** and
**Fig. `fig:budget_pareto`**.

> Note: in the original working tree these runs were labelled the
> "G1 water-budget sweep"; they correspond to the paper's **MO2**.

## Files (now committed)
- `budget_sweep.csv` — parsed frontier (11 cells): columns `file,
  result (= P(safe)), states, transitions, build_sec, check_sec`. The
  scenario `c`, weather, `x(0)`, and budget `B` are encoded in the
  `file` name (`G1_c<c>_w<w>_x40_B<B>.txt`).
- `budget_sweep_raw.zip` — raw Storm `.txt` for the loam reference
  frontier (`c=0.025`, `B ∈ {20,30,40,50,60}`).
- `budget_sweep_more_raw.zip` — raw Storm `.txt` for clay/sandy-loam
  (`c ∈ {0.01,0.05}`, `B ∈ {20,30,40}`).

Loam reference frontier P(safe) vs B = **0.770 / 0.999 / 1.0 / 1.0 / 1.0**
at B = 20/30/40/50/60 mm. The sandy-loam/Dry cell binds at **0.892**
(B=40) — the infeasibility ceiling reported in the paper.

## Regenerate
```bash
bash ../../scripts/run_mo2_budget_sweep.sh 0.025 --storm /path/to/storm
python ../../scripts/utilities/parse_storm_output.py <raw_dir> budget_sweep.csv
```
