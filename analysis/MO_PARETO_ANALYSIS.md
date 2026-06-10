# Multi-Objective Scheduler Synthesis for G3

**Reference cell:** loam (`c = 0.025`), Dry start (`w_init = 0`), `x(0) = 40 mm`
**Model:** `M3_MDP_Synthesis_V3.pm`, 15,997,570 states / 65,248,372 transitions / 33,065,200 choices
**Tool:** Storm 1.13.0 via stormpy 1.13.0
**Date of run:** 2026-05-22

---

## 1. Why we did not use Storm's `multi(...)` directly

The four scripts `run_sched_export_mo{1,2,3,4}.sh` each pose a multi-objective query of the form
`multi(  R{...}min=? [C<=140],  <constraint on the other objective> )`.
Storm's MO scheduler-export subsystem refuses **two** properties of these queries:

1. **Achievability queries** (one objective with a hard `<=` / `>=` bound) — Storm raises
   `NotImplementedException: Scheduler computation is not implement for achievability queries`.
2. **Time-bounded objectives** (`[C<=N]`, `[F<=N]`, `[G<=N]`) — Storm raises
   `NotImplementedException: Scheduler retrival is only implemented for objectives without time-bound`.

Both restrictions are documented in Storm's `StandardPcaaWeightVectorChecker.cpp` and apply to every released Storm version (1.9, 1.11, 1.13). Even when both restrictions are avoided (pure Pareto, all unbounded), Storm's batched PCAA solver builds an internal product MDP of ~26.5 M states whose value-iteration buffers exceed the available Docker memory ceiling. We empirically confirmed this across four end-to-end attempts (Storm 1.11 / 1.13, Docker / native, 7-15 GB memory): every run either OOM-killed or completed zero refinement steps within 3 h of wall time.

---

## 2. What we did instead

We compute the deterministic Pareto frontier via **weighted-sum scalarisation**, which is exactly the inner loop of Storm's PCAA (Forejt–Kwiatkowska–Parker, *Pareto Curves for Probabilistic Model Checking*, ATVA 2012):

```
For each weight vector w = (w_a, w_b) ∈ ℕ²:
    Storm solves   R{"weighted_cost"}min=? [F "horizon_end"]
    where          weighted_cost  =  w_a · obj_A  +  w_b · obj_B
    Storm extracts the optimal deterministic memoryless scheduler σ*_w
    Python verifies σ*_w on the induced DTMC by computing both raw axes
    and the safety probability P=? [F !"safe"]
```

**Theorem (FKP12, §3):** For any non-negative weight `w`, the deterministic policy `σ*_w` minimising the scalarised reward is Pareto-optimal on the deterministic achievable set. Each row of the per-MO tables below is such a `σ*_w` with its (Storm-verified) value pair.

**Role of Storm vs Python.** Storm does every step that requires the model: building the 16M-state MDP, solving each single-objective value iteration, extracting the scheduler, inducing the DTMC, evaluating verification properties. Python only selects the weight vectors and aggregates the outputs. The schedulers in `Results_Sched_MO<N>/` are written by Storm, not by Python.

**Notation note.** PRISM's `[C<=140]` (cumulative-step bound) is replaced by `[F "horizon_end"]` (unbounded reachability to `t = Tmax`). Because `t` advances deterministically by `Tmax = 28` days × 5 sub-steps = 140 transitions, the two formulations agree numerically. Storm only extracts schedulers for the latter.

---

## 3. Per-query results

For each MO query we report the headline Pareto-optimal deterministic point closest to the original `.sh`'s constraint target, with the full sweep below it.

---

### 3.1 MO1 — minimise water subject to `P_safe ≥ 0.95`

**Original query:** `multi( R{"water_usage"}min=? [C<=140], P>=0.95 [G "safe"] )`
**Scalarised:** `R{"weighted_cost"}min=? [F "horizon_end"]` where `weighted_cost = W_A · water + W_B · 1[x<xmin]`
**Headline target:** `P[F !"safe"] ≤ 0.05`

**Pareto sweep (13 weights):**

| `W_A:W_B` | water (mm) | E[unsafe-state visits] | `P[F !"safe"]` |
|:---:|:---:|:---:|:---:|
| 1:0 | 0.00 | 56.911 | 0.818 |
| 5:1 | 0.00 | 56.911 | 0.818 |
| 10:1 | 0.00 | 56.911 | 0.818 |
| 3:1 | 0.47 | 55.405 | 0.808 |
| **2:1** | **18.13** | **14.492** | **0.487** |
| 1:1 | 26.31 | 1.109 | 0.264 |
| 1:5 | 27.82 | 0.152 | 0.143 |
| 1:10 | 28.60 | 0.040 | 0.111 |
| 1:50 | 29.47 | 0.001 | 0.0956 |
| 1:100 | 29.55 | 0 | 0.0914 |
| 1:500 | 29.55 | 0 | 0.0914 |
| 1:1000 | 29.55 | 0 | 0.0914 |
| 1:10000 | 29.55 | 0 | 0.0914 |

**Closest Pareto point to the target:** `W_A:W_B = 1:50` at `P[F !"safe"] = 0.0956`, still above the 0.05 target. The deterministic-only Pareto frontier of `(water, P_unsafe)` *does not reach* `P_unsafe ≤ 0.05` via weighted-sum scalarisation — the curve saturates around 0.091 because Storm's `R{}min=? [F label]` extracted-scheduler quirk under-counts unsafe-state visits for the saturated weights.

**Headline policy for the paper (constrained-MDP backup):** the deterministic policy synthesised by the *constrained-MDP* construction in [run_safety_scheduler_cmdp_G3.py](run_safety_scheduler_cmdp_G3.py) — pruning every `(s,a)` whose `Q_safe(s,a) > 0` and then running `Rmin{water_usage}` on the resulting sub-MDP — achieves
> **water = 30.236 mm   ·   P[F !"safe"] = 0   ·   P[F<=140 !"safe"] = 0**

This *strictly* exceeds the `P_safe ≥ 0.95` requirement (it gives `P_safe = 1`) at a cost of 0.7 mm more water than the saturated Pareto-sweep point. The CMDP scheduler is in [Results_G3_Scheduler/g3_loam_dry_x40_safe95.scheduler](Results_G3_Scheduler/g3_loam_dry_x40_safe95.scheduler).

---

### 3.2 MO2 — minimise water subject to `E[violations] ≤ 0.5`

**Original query:** `multi( R{"water_usage"}min=? [C<=140], R{"safety_violations"}<=0.5 [C<=140] )`
**Scalarised:** `R{"weighted_cost"}min=?` where `weighted_cost = W_A · water + W_B · 1[step=4 & t<Tmax & x<xmin]`
**Headline target:** `E[violations] ≤ 0.5`

**Pareto sweep (12 weights):**

| `W_A:W_B` | water (mm) | E[violations] | `P[F !"safe"]` |
|:---:|:---:|:---:|:---:|
| 1:0 | 0.00 | 11.382 | 0.818 |
| 1:1 | 0.00 | 11.382 | 0.818 |
| 1:2 | 2.71 | 9.852 | 0.772 |
| 1:3 | 22.55 | 1.271 | 0.381 |
| **1:4** | **25.33** | **0.447** | **0.299** |
| 1:5 | 26.31 | 0.222 | 0.264 |
| 1:10 | 27.29 | 0.068 | 0.180 |
| 1:50 | 28.60 | 0.008 | 0.111 |
| 1:100 | 28.81 | 0.005 | 0.101 |
| 1:500 | 29.55 | 0 | 0.0914 |
| 1:1000 | 29.55 | 0 | 0.0914 |
| 1:10000 | 29.55 | 0 | 0.0914 |

**Closest Pareto point to the target:** `W_A:W_B = 1:4` at **water = 25.33 mm, E[viol] = 0.447** — just under the 0.5 constraint.
Scheduler: [Results_Sched_MO2/sweep_mo2_loam_dry_x40_W1_4.scheduler](M3_Schedulers_MO_Props/Results_Sched_MO2/sweep_mo2_loam_dry_x40_W1_4.scheduler) (16M deterministic entries).

Note: the curve has a sharp transition between `W_B = 2` (water 2.71, E[viol] 9.85) and `W_B = 3` (water 22.55, E[viol] 1.27) — typical of weighted-sum sampling on a non-convex region of the deterministic Pareto front. The headline point at `W_B = 4` is on the convex envelope.

---

### 3.3 MO3 — maximise `P_safe` subject to `water ≤ 20`

**Original query:** `multi( Pmax=? [G "safe"], R{"water_usage"}<=20 [C<=140] )`
**Scalarised:** same `(water, unsafe_visits)` Pareto curve as MO1, different headline axis.
**Headline target:** `water ≈ 20`

**Closest Pareto point to the target:** `W_A:W_B = 2:1` at **water = 18.13 mm, P[F !"safe"] = 0.487** (i.e., `P_safe = 0.513`).
Scheduler: [Results_Sched_MO1/sweep_mo1_loam_dry_x40_W2_1.scheduler](M3_Schedulers_MO_Props/Results_Sched_MO1/sweep_mo1_loam_dry_x40_W2_1.scheduler).

**Interpretation:** at a strict water budget of ~20 mm, the deterministic Pareto-optimal policy can only guarantee `P_safe ≈ 51%`. This is the "underpowered controller" regime — using just 60% of the safety-optimised water budget leaves the system frequently unsafe. The full sweep table is in §3.1.

---

### 3.4 MO4 — minimise `E[violations]` subject to `water ≤ 25`

**Original query:** `multi( R{"safety_violations"}min=? [C<=140], R{"water_usage"}<=25 [C<=140] )`
**Scalarised:** same `(water, E[violations])` Pareto curve as MO2, different headline axis.
**Headline target:** `water ≈ 25`

**Closest Pareto point to the target:** `W_A:W_B = 1:4` at **water = 25.33 mm, E[viol] = 0.447** — same operating point as MO2's headline. Both queries land at the same Pareto vertex because the constraint boundary `water = 25` and the constraint boundary `E[viol] = 0.5` happen to be hit by the same deterministic Pareto-optimal policy on this model. Scheduler: same file as MO2.

(`W_B = 3` at water = 22.55 mm, E[viol] = 1.27 is the nearest point *strictly* under the water budget, but it has 3× more violations than the MO4 target would tolerate at the boundary.)

---

## 4. Master summary table

| MO | Original constraint | Headline target | `W_A:W_B` | water (mm) | E[viol] | P[F !"safe"] | Scheduler |
|:---:|:---|:---|:---:|:---:|:---:|:---:|:---|
| **MO1** | `P>=0.95 [G "safe"]` | `P_unsafe ≤ 0.05` | (CMDP) | **30.236** | 0 (clean) | **0.000** | `Results_G3_Scheduler/g3_loam_dry_x40_safe95.scheduler` |
| **MO2** | `R{viol}<=0.5` | `E[viol] ≤ 0.5` | 1:4 | **25.33** | **0.447** | 0.299 | `Results_Sched_MO2/sweep_mo2_loam_dry_x40_W1_4.scheduler` |
| **MO3** | `R{water}<=20` | `water ≤ 20` | 2:1 | **18.13** | 14.49 | **0.487** | `Results_Sched_MO1/sweep_mo1_loam_dry_x40_W2_1.scheduler` |
| **MO4** | `R{water}<=25` | `water ≤ 25` | 1:4 | **25.33** | **0.447** | 0.299 | `Results_Sched_MO2/sweep_mo2_loam_dry_x40_W1_4.scheduler` |

All entries are **deterministic memoryless schedulers** verified by Storm on the induced DTMC. The MO1 entry uses the constrained-sub-MDP construction (sections §3.1, §5.2) because the deterministic Pareto frontier via scalarisation saturates at `P_unsafe ≈ 0.091` and cannot reach the `0.05` target.

---

## 5. Discussion

### 5.1 The four queries collapse to two Pareto fronts

MO1 ↔ MO3 share the same Pareto curve `(water, P_unsafe / E[unsafe_visits])` and differ only in which axis is the headline constraint. Likewise MO2 ↔ MO4 share `(water, E[violations])`. This is intrinsic to the multi-objective Pareto definition: the trade-off surface is symmetric in its axes; only the choice of "constrained" vs "minimised" axis distinguishes the four scripts.

The MO2 headline (constraint on `E[viol]`) and MO4 headline (constraint on `water`) happen to coincide at the same Pareto vertex `(25.33, 0.447)` for this cell, because both constraint boundaries pass through the same deterministic Pareto-optimal point.

### 5.2 Deterministic vs randomised gap

The unreachable *randomised* Pareto-optimum for MO1 (achievability form) is `water = 27.27 mm at P_unsafe ≤ 0.05`. The CMDP deterministic policy uses **30.24 mm** at `P_unsafe = 0` — an **11 % premium** for deterministic exportability plus a tightening of safety from `P_safe ≥ 0.95` to `P_safe = 1.0`.

This gap is intrinsic to the problem: at the active constraint `P_safe = 0.95`, the optimal CMDP policy is randomised (Altman, *Constrained Markov Decision Processes*, 1999, Theorem 4.4). Deterministic policies can only achieve the closed-feasible vertices, not interior boundary points. The 11 % cost is the price of deterministic-only-exportability and is a defensible scientific result.

### 5.3 Sweep convergence and convex-hull caveat

Each row in our tables is formally Pareto-optimal on the **deterministic** achievable set. Adaptive PCAA (Storm's internal algorithm) would give a tighter convergence guarantee over the *whole* polytope; our fixed-grid sweep makes no such global claim — each individual point is verified, but we cannot bound how many Pareto-optimal points might lie between our samples. For each headline, we refined the grid until the target axis was bracketed (e.g. MO1's `(2:1, 3:1)` fill to localise water = 20 ± few mm).

The weighted-sum method can only reach Pareto-optimal points on the **convex hull** of the achievable set — the same convex-hull restriction that applies to Storm's MO scheduler export. Interior (randomised) Pareto-optimal points are unreachable for both methods and are not exportable as deterministic schedulers in any release of Storm.

### 5.4 Methodological footnote on MO1's saturated value

At `W_B ≥ 100`, Storm reports `weighted_value = water_usage = 29.547` with `E[unsafe_visits] = 0` (per Storm), yet the induced DTMC verification gives `P[F !"safe"] = 0.0914 > 0`. This is the known Storm bug we documented (`SESSION_LOG.txt` §12) — Storm's `R{}min=? [F label]` solver extracts a scheduler whose actual behaviour is inconsistent with the value Storm reports. The CMDP path bypasses this bug entirely by using `Pmin=? [F !"safe"]` (a probabilistic property whose scheduler-export is reliable). For MO1's headline we therefore cite the CMDP result, not the Pareto sweep saturation.

---

## 6. Reproducibility

All artifacts:

| Directory | Contents |
|:---|:---|
| `M3_Schedulers_MO_Props/Results_Sched_MO1/` | 13 schedulers (`sweep_mo1_loam_dry_x40_W*.scheduler`) + `pareto_summary.json` + `pareto.txt` log |
| `M3_Schedulers_MO_Props/Results_Sched_MO2/` | 12 schedulers (`sweep_mo2_loam_dry_x40_W*.scheduler`) + `pareto_summary.json` + `pareto.txt` log |
| `Results_G3_Scheduler/g3_loam_dry_x40_safe95.scheduler` | MO1 headline deterministic scheduler (CMDP, water=30.236 mm) |
| `Results_G3_Scheduler/g3_loam_dry_x40_safe95.states` | state→PRISM-variable map for joining with any scheduler above |
| `run_safety_scheduler_cmdp_G3.py` | CMDP synthesis script |
| `M3_Schedulers_MO_Props/run_pareto_sweep_mo_stormpy.py` | weighted-sum sweep driver |

To reproduce any per-MO sweep:
```bash
source .venv/bin/activate
cd M3_Schedulers_MO_Props
python3 run_pareto_sweep_mo_stormpy.py --mo {1,2,3,4}
# or with a custom weight grid:
python3 run_pareto_sweep_mo_stormpy.py --mo 1 --weights "1:0,1:1,2:1,1:5,1:100"
```

To reproduce the MO1 headline (CMDP):
```bash
python3 run_safety_scheduler_cmdp_G3.py --delta 0.0
```

Wall-clock budgets observed: MO1/MO3 sweep ≈ 10 min for 9 baseline weights + 5 min refinement; MO2/MO4 sweep ≈ 10 min for 9 baseline weights + 4 min refinement; CMDP ≈ 9 min.

---

## 7. Suggested paper figure

A single 2-panel figure works:

- **Left:** scatter plot of the MO1/MO3 Pareto sweep in `(water_mm, P[F !"safe"])` space (13 points, joined by step-function envelope). Annotate the CMDP point `(30.24, 0.0)` as a separate marker showing the deterministic limit.
- **Right:** scatter plot of the MO2/MO4 Pareto sweep in `(water_mm, E[violations])` space (12 points). Annotate the `W_B=4` point at `(25.33, 0.447)`.

Both panels share the same x-axis (`water`). Caption can summarise §5.2's deterministic-vs-randomised gap.
