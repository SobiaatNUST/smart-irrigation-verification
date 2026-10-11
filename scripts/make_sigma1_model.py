#!/usr/bin/env python3
"""
Derive the "almost-surely-safe" analysis model used to compute sigma_1.

sigma_1 is the cheapest deterministic policy that keeps x >= xmin at every
time step with probability one.  The committed artefact obtains it with a
stormpy constrained-MDP construction (prune every state-action pair whose
minimal unsafe-reachability probability is positive, then minimise water on the
remaining sub-MDP).  That construction can be expressed directly in PRISM, so
that it runs on the Storm command line and needs no Python bindings:

  1. make an unsafe state absorbing, by splitting the soil-update command on
     x >= xmin and adding a trap command for x < xmin;
  2. define the target  horizon_end_safe = (t = Tmax & x >= xmin).

Then, for any scheduler sigma,
     P_sigma[ F "horizon_end_safe" ]  =  P_sigma[ G "safe" ],
because the run reaches the target exactly when it is safe at every step.
Storm's expected-reachability-reward semantics assign +infinity when the target
is not reached almost surely, so

     R{"water_usage"}min=? [ F "horizon_end_safe" ]

minimises expected water over precisely the schedulers with P[G safe] = 1, and
its optimum is attained by a deterministic memoryless scheduler.  That value is
sigma_1's water use.  A finite result therefore certifies that an almost-surely
safe policy exists; "inf" certifies that none does.

Only the analysis model is changed; the model of record is untouched.
"""
import re, sys, pathlib

def derive(src: str, xinit: int) -> str:
    src = re.sub(r'x : \[0\.\.100\] init \d+', f'x : [0..100] init {xinit}', src)
    old = """    [] step=4 & t<Tmax ->
        (x' = min(100, max(0, floor(x*(1-c) + u + p_hat + xi - e_hat - eta)))) &
        (t' = t+1) &
        (step'=0);"""
    new = """    // [sigma_1 analysis model] normal update, only while currently safe
    [] step=4 & t<Tmax & x>=xmin ->
        (x' = min(100, max(0, floor(x*(1-c) + u + p_hat + xi - e_hat - eta)))) &
        (t' = t+1) &
        (step'=0);

    // [sigma_1 analysis model] an unsafe state is absorbing, so a run that
    // ever becomes unsafe never reaches "horizon_end_safe"
    [] step=4 & t<Tmax & x<xmin -> (x'=x) & (t'=t) & (step'=4);"""
    if src.count(old) != 1:
        sys.exit("soil-update command not found verbatim")
    src = src.replace(old, new, 1)
    src += '\n// [sigma_1 analysis model] target: horizon reached while safe\n'
    src += 'label "horizon_end_safe" = (t = Tmax & x >= xmin);\n'
    return src

if __name__ == "__main__":
    inp, out, xinit = sys.argv[1], sys.argv[2], int(sys.argv[3])
    pathlib.Path(out).write_text(derive(pathlib.Path(inp).read_text(), xinit))
    print("wrote", out)
