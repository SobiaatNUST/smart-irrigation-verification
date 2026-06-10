# results/sensitivity — sensitivity to initial soil moisture

Backs **Table `tab:sens`** of the paper. Verified for
`x(0) ∈ {20, 30, 40, 50} mm` for the deterministic controllers M1/M2
(from `../deterministic/`) and for `x(0) ∈ {30, 40} mm` for the
M3 σ*₀.₉₅ synthesis.

## Files (now committed)
- `sensitivity.csv` — the M3 σ*₀.₉₅ sensitivity sweep
  (query `multi(R{"water_usage"}min=? [C<=140], P>=0.95 [G "safe"])`
  at varied `x(0)`), with full metadata columns
  (`c, w_name, xinit, query_desc, result, states, …`). The M1/M2 rows
  of `tab:sens` are read from `../deterministic/M1_parsed.csv` and
  `M2_parsed.csv`.

## Regenerate
```bash
bash ../../scripts/run_sensitivity.sh --storm /path/to/storm
```
(The M1/M2 portions come from the deterministic sweeps; no extra run.)
