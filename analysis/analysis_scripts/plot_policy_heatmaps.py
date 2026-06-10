#!/usr/bin/env python3
"""
Generate 4-panel policy-heatmap figure for the SIS paper.

Each panel shows a (soil-moisture x, weather state w) -> irrigation action u
slice of one deterministic scheduler. The slice fixes step=4 (decision
epoch), t=0 (initial day), eta=0, xi=0 (no realised noise), and aggregates
the chosen action by mean over forecast variables (p_hat, e_hat).

Panel-to-scheduler mapping (LABELS IN PLOT vs the underlying .sh names):
  Panel 1 = "MO1"        <- original MO1 CMDP scheduler
  Panel 2 = "MO2"        <- original MO3 sweep point (W_A=2, W_B=1)
  Panel 3 = "MO3 / MO4"  <- original MO2/MO4 vertex (W_A=1, W_B=4)
  Panel 4 = "Reference"  <- pure water-min sweep extreme (W_A=1, W_B=0)
"""

from __future__ import annotations

import re
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm
from matplotlib.cm import ScalarMappable

import stormpy


PROJECT_DIR = Path(__file__).resolve().parents[1]
MODEL_FILE = PROJECT_DIR / "M3_MDP_Synthesis_V3.pm"
OUT_PDF = Path(__file__).resolve().parent / "policy_heatmaps.pdf"

C_REF = "0.025"
W_INIT_REF = "0"
XINIT = 40

PANELS = [
    {
        "title": "MO1",
        "subtitle": r"safety-saturated  (sweep $W_A{:}W_B = 1{:}10000$)",
        "path": PROJECT_DIR / "M3_Schedulers_MO_Props"
                            / "Results_Sched_MO1"
                            / "sweep_mo1_loam_dry_x40_W1_10000.scheduler",
    },
    {
        "title": "MO2",
        "subtitle": r"$R^{w} \leq 20$  (sweep $W_A{:}W_B = 2{:}1$)",
        "path": PROJECT_DIR / "M3_Schedulers_MO_Props"
                            / "Results_Sched_MO1"
                            / "sweep_mo1_loam_dry_x40_W2_1.scheduler",
    },
    {
        "title": "MO3 / MO4",
        "subtitle": r"$E[\text{viol}] \leq 0.5$ / $R^{w} \leq 25$  ($W_A{:}W_B = 1{:}4$)",
        "path": PROJECT_DIR / "M3_Schedulers_MO_Props"
                            / "Results_Sched_MO2"
                            / "sweep_mo2_loam_dry_x40_W1_4.scheduler",
    },
    {
        "title": "Reference",
        "subtitle": r"pure water-min  ($W_A{:}W_B = 1{:}0$)",
        "path": PROJECT_DIR / "M3_Schedulers_MO_Props"
                            / "Results_Sched_MO1"
                            / "sweep_mo1_loam_dry_x40_W1_0.scheduler",
    },
]

WEATHER_LABELS = {0: "Dry", 1: "Moderate", 2: "Wet"}


def patch_model(src: Path, xinit: int, out: Path) -> None:
    text = src.read_text()
    text, n = re.subn(r"x : \[0\.\.100\] init [0-9]+",
                      f"x : [0..100] init {xinit}", text)
    if n == 0:
        raise RuntimeError(f"Could not patch xinit in {src}")
    out.write_text(text.rstrip() + '\n\nlabel "horizon_end" = (t=Tmax);\n')


def build_model():
    temp = PROJECT_DIR / "policy_plot_temp.pm"
    patch_model(MODEL_FILE, XINIT, temp)
    prism = stormpy.parse_prism_program(str(temp), prism_compat=True)
    constants = stormpy.parse_constants_string(
        prism.expression_manager, f"c={C_REF},w_init={W_INIT_REF}"
    )
    prism = prism.define_constants(constants).substitute_constants()
    props = stormpy.parse_properties_for_prism_program(
        'R{"water_usage"}=? [F "horizon_end"]', prism
    )
    opts = stormpy.BuilderOptions([p.raw_formula for p in props])
    opts.set_build_state_valuations(True)
    opts.set_build_all_reward_models(True)
    opts.set_build_all_labels(True)
    print("Building MDP...")
    t0 = time.time()
    model = stormpy.build_sparse_model_with_options(prism, opts)
    print(f"  states={model.nr_states}  build={time.time()-t0:.1f}s")
    try:
        temp.unlink()
    except OSError:
        pass
    return model


_VAR_PATT = re.compile(r"(\w+)=(-?\d+)")


def extract_decision_states(model) -> pd.DataFrame:
    """Return DataFrame of states at the decision epoch (step=1, no realised
    noise). t is left free so x can span its full range across days."""
    sv = model.state_valuations
    n = model.nr_states
    print(f"Filtering {n} states to (step=1, eta=0, xi=0)...")
    t0 = time.time()
    records = []
    for s in range(n):
        vars_ = dict(_VAR_PATT.findall(sv.get_string(s)))
        if vars_["step"] != "1":
            continue
        if vars_["eta"] != "0":
            continue
        if vars_["xi"] != "0":
            continue
        records.append({
            "state_id": s,
            "w_state": int(vars_["w_state"]),
            "x":       int(vars_["x"]),
            "p_hat":   int(vars_["p_hat"]),
            "e_hat":   int(vars_["e_hat"]),
            "t":       int(vars_["t"]),
        })
    df = pd.DataFrame(records)
    print(f"  kept {len(df)} decision states  wall={time.time()-t0:.1f}s")
    return df


def derive_action_to_u_map(model, decision_df) -> dict:
    """Map action_id -> u value by inspecting transitions from a sample state."""
    if decision_df.empty:
        return {}
    s = int(decision_df.iloc[0]["state_id"])
    sv = model.state_valuations
    matrix = model.transition_matrix
    start = matrix.get_row_group_start(s)
    end = matrix.get_row_group_end(s)
    mapping = {}
    for a, row_idx in enumerate(range(start, end)):
        row = matrix.get_row(row_idx)
        for entry in row:
            next_state = entry.column
            vars_ = dict(_VAR_PATT.findall(sv.get_string(next_state)))
            mapping[a] = int(vars_["u"])
            break
    print(f"  action_id -> u: {mapping}")
    return mapping


def load_scheduler(path: Path) -> pd.DataFrame:
    print(f"Loading {path.name}...")
    return pd.read_csv(path, sep=" ", header=None,
                       names=["state_id", "action_id"],
                       dtype=np.int64)


def build_policy_grid(decision_df, scheduler_df, action_to_u) -> pd.DataFrame:
    """Return DataFrame indexed by w_state with columns = x values; entries = mean u."""
    merged = decision_df.merge(scheduler_df, on="state_id")
    merged["u"] = merged["action_id"].map(action_to_u).fillna(0).astype(int)
    agg = (merged.groupby(["w_state", "x"])["u"]
                  .mean()
                  .reset_index())
    pivot = agg.pivot(index="w_state", columns="x", values="u")
    # Ensure full x range 0..100; fill missing with NaN
    full_x = range(0, 101)
    pivot = pivot.reindex(columns=full_x)
    pivot = pivot.reindex(index=[0, 1, 2])
    return pivot


def main():
    model = build_model()
    decision_df = extract_decision_states(model)
    action_to_u = derive_action_to_u_map(model, decision_df)

    grids = {}
    for panel in PANELS:
        sched_df = load_scheduler(panel["path"])
        grids[panel["title"]] = build_policy_grid(
            decision_df, sched_df, action_to_u
        )

    # ------- Plot -------
    fig, axes = plt.subplots(4, 1, figsize=(7.0, 6.8), sharex=True)
    fig.subplots_adjust(hspace=0.85, top=0.93, bottom=0.10,
                        left=0.10, right=0.88)

    u_levels = sorted(set(action_to_u.values()))
    if not u_levels:
        u_levels = [0, 2, 4, 6, 8, 10]
    umax = max(u_levels)
    cmap = plt.colormaps["viridis"]

    for ax, panel in zip(axes, PANELS):
        grid = grids[panel["title"]].values  # shape (3, 101)
        im = ax.imshow(
            grid, aspect="auto", cmap=cmap,
            vmin=0, vmax=umax, origin="lower",
            extent=[-0.5, 100.5, -0.5, 2.5],
            interpolation="nearest",
        )
        ax.set_yticks([0, 1, 2])
        ax.set_yticklabels(["Dry", "Moderate", "Wet"], fontsize=9)
        ax.set_ylabel("Weather", fontsize=9)
        ax.set_title(f"{panel['title']} — {panel['subtitle']}",
                     fontsize=9.5, loc="left", pad=6)
        # x_min marker (safety threshold)
        ax.axvline(25, color="white", linestyle=":", linewidth=0.8, alpha=0.7)

    axes[-1].set_xlabel("Soil moisture $x$ (mm)", fontsize=10)
    axes[-1].set_xticks([0, 20, 25, 40, 60, 80, 100])

    cbar = fig.colorbar(
        im, ax=axes, orientation="vertical",
        fraction=0.025, pad=0.02, ticks=u_levels,
    )
    cbar.set_label("Irrigation action $u$ (mm)", fontsize=9.5)
    cbar.ax.tick_params(labelsize=8)

    plt.savefig(OUT_PDF, dpi=300, bbox_inches="tight")
    print(f"\nSaved {OUT_PDF}")


if __name__ == "__main__":
    sys.exit(main())
