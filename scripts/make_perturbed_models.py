#!/usr/bin/env python3
"""E4/E5: write probability-perturbed variants of M3_mdp_synthesis.pm.
Only const double values / Forecast transition literals change; state space is identical."""
import re, os, sys, pathlib
SRC = pathlib.Path(__file__).parent.parent / 'SIS_GIT_REPO/models/M3/M3_mdp_synthesis.pm'
OUT = pathlib.Path(__file__).parent / 'models_perturbed'; OUT.mkdir(exist_ok=True)
src = SRC.read_text()

def inflate(support, probs, k):
    """Scale the spread of a discrete distribution by k about its mean, keeping the
    mean fixed and the support fixed: p'_i = p_i + (k-1)*... via moment matching
    on a two-parameter family: move mass from the modal bin to the tails proportionally."""
    mean = sum(s*p for s,p in zip(support,probs))
    var  = sum(p*(s-mean)**2 for s,p in zip(support,probs))
    target = var * k*k
    # move mass alpha from the modal bin to the outer bins, split so the mean is preserved
    i0 = max(range(len(probs)), key=lambda i: probs[i])
    lo, hi = 0, len(probs)-1
    dlo, dhi = support[lo]-mean, support[hi]-mean          # dlo<0<dhi
    # mass a to lo, b to hi with a*dlo + b*dhi = 0 (mean preserved) => a = -b*dhi/dlo
    # variance increase = a*(dlo^2 - d0^2) + b*(dhi^2 - d0^2) where d0 = support[i0]-mean
    d0 = support[i0]-mean
    ratio = -dhi/dlo
    dv_per_b = ratio*(dlo**2-d0**2) + (dhi**2-d0**2)
    b = (target-var)/dv_per_b; a = ratio*b
    new = list(probs); new[lo]+=a; new[hi]+=b; new[i0]-=(a+b)
    assert min(new) >= -1e-12, f"inflation {k} infeasible for {probs}: {new}"
    new=[round(max(0,p),6) for p in new]; new[i0]=round(1-sum(new[:i0])-sum(new[i0+1:]),6)
    return new

def sub_const(text, name, val):
    text2, n = re.subn(rf'(const double {name}\s*=\s*)[0-9.]+;', rf'\g<1>{val};', text)
    assert n == 1, name
    return text2

ETA = dict(names=['prob_eta_m2','prob_eta_m1','prob_eta_0','prob_eta_p1','prob_eta_p2'], sup=[-2,-1,0,1,2], p=[0.03,0.12,0.50,0.25,0.10])
XI0 = dict(names=['prob_xi_zero_p0','prob_xi_zero_p1','prob_xi_zero_p2'], sup=[0,1,2], p=[0.65,0.25,0.10])
XIL = dict(names=['prob_xi_low_m2','prob_xi_low_m1','prob_xi_low_0','prob_xi_low_p1','prob_xi_low_p2'], sup=[-2,-1,0,1,2], p=[0.05,0.15,0.45,0.25,0.10])
XIH = dict(names=['prob_xi_high_m5','prob_xi_high_m2','prob_xi_high_0','prob_xi_high_p2','prob_xi_high_p5'], sup=[-5,-2,0,2,5], p=[0.08,0.25,0.40,0.19,0.08])

for k in (1.25, 1.5):   # x2.0 is infeasible on the bounded 5-point supports (negative modal mass)
    t = src; hdr = [f"// E4 variant: xi/eta spread x{k}, means preserved"]
    for D in (ETA, XIL, XIH):
        try: newp = inflate(D['sup'], D['p'], k)
        except AssertionError as e: print("WARN", e); newp = None
        if newp:
            for n,v in zip(D['names'], newp): t = sub_const(t, n, v)
            hdr.append(f"//   {D['names'][0].rsplit('_',1)[0]}: {D['p']} -> {newp}")
    # R1 (p_hat=0) has one-sided support {0,1,2}; the mean cannot be preserved while inflating,
    # so R1 is inflated by moving mass 0->2 and the mean shift is recorded.
    p=XI0['p']; shift=min(0.15*(k-1), p[0]-0.05); newp=[round(p[0]-shift,6),p[1],round(p[2]+shift,6)]
    for n,v in zip(XI0['names'], newp): t = sub_const(t, n, v)
    hdr.append(f"//   xi (p_hat=0): {p} -> {newp}  (mean {sum(s*q for s,q in zip(XI0['sup'],p)):.3f} -> {sum(s*q for s,q in zip(XI0['sup'],newp)):.3f})")
    (OUT/f'xi_eta_x{k}.pm').write_text("\n".join(hdr)+"\n"+t); print("\n".join(hdr))

# E5: P(Dry|Dry) variants; row renormalised keeping the Mod:Wet ratio 2:1
for pdd in (0.60, 0.80):
    rest = 1-pdd; pm, pw = round(rest*2/3,4), round(rest/3,4)
    t = src.replace("0.70:(p_hat'=0) & (e_hat'=4) & (w_state'=0) & (step'=1) +\n        0.20:(p_hat'=2) & (e_hat'=3) & (w_state'=1) & (step'=1) +\n        0.10:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);",
                    f"{pdd}:(p_hat'=0) & (e_hat'=4) & (w_state'=0) & (step'=1) +\n        {pm}:(p_hat'=2) & (e_hat'=3) & (w_state'=1) & (step'=1) +\n        {pw}:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);")
    assert t != src, "Dry-row literal not found"
    (OUT/f'pdd_{pdd}.pm').write_text(f"// E5 variant: P(Dry|Dry)={pdd}, P(Mod|Dry)={pm}, P(Wet|Dry)={pw}\n"+t)
    print(f"pdd_{pdd}.pm written")
