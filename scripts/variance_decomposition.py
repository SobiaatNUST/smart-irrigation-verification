#!/usr/bin/env python3
"""
Variance decomposition (ANOVA sum-of-squares) of the committed verification
results over the factorial design, addressing Reviewer 3, General Comment 5.

Inputs (all COMMITTED in SIS_GIT_REPO/results):
  deterministic/M1_parsed.csv          M1  P(safe), water   x(0) in {20,30,40,50}
  deterministic/M2_parsed.csv          M2  water            x(0) in {20,30,40,50}
  mo1/tier1_named_policies.csv         M3 sigma*_0.95 water at x(0)=40
  sensitivity/sensitivity.csv          M3 sigma*_0.95 water at x(0)=30

Responses:
  (a) M1 P(safe)  over soil x weather x x0         (x0 in {30,40,50}; x0=20 is identically 0 and excluded)
  (b) M2 water    over soil x weather x x0         (x0 in {30,40,50})
  (c) M3 water    over soil x weather x x0         (x0 in {30,40})
  (d) pooled water over controller x soil x weather at x0 in {30,40} for M2, M3

Method: full-factorial (balanced) ANOVA identity
  SS_total = sum_k SS_k (main effects) + sum SS_jk (2-way) + SS_3way
For a balanced design the effect sums of squares are orthogonal and sum
exactly to SS_total, so the share SS_k / SS_total is the fraction of the
observed variability attributable to that factor (eta-squared).
Standard library only.
"""
import csv, itertools, sys
from collections import defaultdict
import os; R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "results") + os.sep

def rd(p): return list(csv.DictReader(open(R+p)))

soil = {'0.01':'clay','0.025':'loam','0.05':'sandy'}
wx   = {'0':'Dry','1':'Mod','2':'Wet'}

def anova(cells, factors):
    """cells: dict[tuple(levels)] -> value, complete balanced grid."""
    levels=[sorted({k[i] for k in cells}) for i in range(len(factors))]
    N=len(cells); gm=sum(cells.values())/N
    sst=sum((v-gm)**2 for v in cells.values())
    def mean_over(fix):  # fix: dict idx->level
        vals=[v for k,v in cells.items() if all(k[i]==l for i,l in fix.items())]
        return sum(vals)/len(vals)
    out={}
    # main effects
    eff={}
    for i,f in enumerate(factors):
        eff[(i,)]={ (l,): mean_over({i:l})-gm for l in levels[i]}
        n=N/len(levels[i]); out[f]=n*sum(e**2 for e in eff[(i,)].values())
    # two-way
    for i,j in itertools.combinations(range(len(factors)),2):
        d={}
        for li in levels[i]:
            for lj in levels[j]:
                d[(li,lj)]=mean_over({i:li,j:lj})-gm-eff[(i,)][(li,)]-eff[(j,)][(lj,)]
        eff[(i,j)]=d; n=N/(len(levels[i])*len(levels[j]))
        out[factors[i]+'x'+factors[j]]=n*sum(e**2 for e in d.values())
    # residual (3-way etc.)
    out['residual']=sst-sum(out.values())
    return sst,out

def report(title,cells,factors,unit):
    sst,out=anova(cells,factors)
    print(f"\n== {title}  (n={len(cells)}, SS_total={sst:.4g} {unit}^2)")
    for k,v in out.items():
        print(f"   {k:16s} SS={v:10.4g}   share={100*v/sst:6.1f}%")
    return sst,out

# ---- (a) M1 P(safe) ----
m1={}
for r in rd('deterministic/M1_parsed.csv'):
    if r['xinit'] in ('30','40','50'):
        m1[(soil[r['c']],wx[r['w']],r['xinit'])]=float(r['p_safe'])
resA=report("M1  P(safe)   soil x weather x x0{30,40,50}",m1,['soil','weather','x0'],'')

# ---- (b) M2 water ----
m2={}
for r in rd('deterministic/M2_parsed.csv'):
    if r['xinit'] in ('30','40','50'):
        m2[(soil[r['c']],wx[r['w']],r['xinit'])]=float(r['water_usage'])
resB=report("M2  water     soil x weather x x0{30,40,50}",m2,['soil','weather','x0'],'mm')

# ---- (c) M3 sigma*_0.95 water ----
m3={}
for r in rd('mo1/tier1_named_policies.csv'):
    if r['query_id']=='P2_safe95': m3[(soil[r['c']],wx[r['w_init']],'40')]=float(r['result'])
import re as _re
for line in open(R+'sensitivity/sensitivity.csv').read().splitlines()[1:]:
    # the property field contains an unquoted comma; take the numeric field that follows it
    m=_re.search(r'T3,T3_c([0-9.]+)_w(\d)_x30_.*?\[G "safe"\]\)",([0-9.]+),',line)
    if m: m3[(soil[m.group(1)],wx[m.group(2)],'30')]=float(m.group(3))
resC=report("M3  sigma*0.95 water  soil x weather x x0{30,40}",m3,['soil','weather','x0'],'mm')

# ---- (d) pooled water M2 vs M3, x0 in {30,40} ----
pool={}
for k,v in m2.items():
    if k[2] in ('30','40'): pool[('M2',)+k]=v
for k,v in m3.items(): pool[('M3',)+k]=v
resD=report("Water, controller{M2,M3} x soil x weather x x0{30,40}",pool,['ctrl','soil','weather','x0'],'mm')

# ---- LaTeX table rows (shares) ----
def row(name,res,keys):
    sst,out=res
    return name+" & "+" & ".join(f"{100*out.get(k,0)/sst:.1f}" for k in keys)+" \\\\"
keys=['soil','weather','x0','soilxweather','soilxx0','weatherxx0','residual']
print("\nLaTeX rows (percent of total sum of squares):")
print("Response & Soil & Weather & $x(0)$ & S$\\times$W & S$\\times x(0)$ & W$\\times x(0)$ & Resid. \\\\")
print(row("M1 $P(\\mathsf{safe})$",resA,keys))
print(row("M2 water",resB,keys))
print(row("M3 $\\sigma^{*}_{0.95}$ water",resC,keys))
sst,out=resD
print("pooled: ", {k: round(100*v/sst,1) for k,v in out.items()})
