# results/mo1/theta_sweep — MO1 θ-axis Pareto sweep

Paper query **MO1** swept over the safety target θ:
`multi(R{"water_usage"}min=? [C<=140], P>=θ [G "safe"])`. Backs the
θ-axis frontier **Fig. `fig:pareto`** and the operating-point plane
**Fig. `fig:m3pareto`**.

> Note: originally labelled the "T2 Pareto frontier" sweep.

## Files (now committed)
- `theta_sweep.csv` — frontier at the loam reference cell
  (`c=0.025`, Dry, `x(0)=40`) over `θ ∈ {0.60 … 0.99}`, with full
  metadata (`theta, query_desc, result_min_water, states, …`).
- `theta_sweep_raw.zip` — raw Storm `.txt` for the reference sweep.
- `theta_sweep_ext_raw.zip` — extension raws covering the Moderate/Wet
  weather frontiers used in `fig:m3pareto`.

## Regenerate
```bash
bash ../../../scripts/run_mo1_theta_sweep.sh 0.025
```
