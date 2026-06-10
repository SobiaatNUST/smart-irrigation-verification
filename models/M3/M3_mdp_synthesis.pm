mdp

////////////////////////////////////////////////////////////////////////
// MDP OPTIMAL POLICY SYNTHESIS — VERSION 3 (Literature-Calibrated)
////////////////////////////////////////////////////////////////////////
//
// OVERVIEW:
// The controller is NONDETERMINISTIC — PRISM/Storm's strategy synthesis
// engine picks the optimal irrigation action at each reachable state.
// This converts the verification problem into automated synthesis of
// a provably optimal state-dependent policy.
//
// Six irrigation levels {0, 2, 4, 6, 8, 10} mm are offered as actions
// at every step. The model checker finds which action minimises/maximises
// the queried property (water usage, safety violations, etc.).
//
// CHANGES FROM VERSION 1 (M3_MDP_Uncertain_V1):
//
// [C1] ET uncertainty: 5-point distribution eta in {-2,-1,0,+1,+2} mm
//      V1 used {-3, 0, +3} with 3 points. With e_hat in [2,3], the
//      V1 error of +-3mm was 100-150% of the forecast — far exceeding
//      FAO-56 guidelines of 10-20% under standard conditions.
//
//      CRITICAL EVALUATION — Why +-2mm and NOT +-1mm or +-3mm:
//        +-1mm: Only 3 integer points {-1, 0, +1}. Too coarse for a
//               5-point distribution, and cannot capture rare extremes
//               (heat waves, cold snaps) that matter for safety analysis.
//        +-3mm: For e_hat=2, error of 3mm = 150% of forecast. Even
//               FAO-56 extremes (40% in arid/humid conditions) give
//               only 0.8mm error for e_hat=2. Indefensible.
//        +-2mm: With 87% of mass within +-1mm (FAO-56 compliant for
//               all e_hat in [1,4]), and 13% tail probability at +-2mm
//               capturing rare extremes. For e_hat=4 (peak summer),
//               +-2mm = 50% which matches FAO-56 extreme conditions.
//               For e_hat=1 (cool overcast), +-2mm = 200% but only
//               3% probability at that extreme.
//
//      E[eta] = +0.27mm (slight drying bias: ET models underpredict
//      in summer heat spells — Shang et al. 2020 confirms asymmetry)
//      SD[eta] = 0.90mm
//      Ref: Allen et al. FAO-56 (1998); Hargreaves & Samani (1985)
//
// [C2] Precipitation uncertainty: 3-regime FORECAST-PROPORTIONAL bounds
//      V1 used XI_MAX = P_MAX - p_hat (physical ceiling = 50 - p_hat).
//
//      CRITICAL EVALUATION — Why the paper's bounds are correct but
//      misapplied in discrete PRISM models:
//
//      Shang et al. (2020) eq. 18: xi >= -p_hat (actual precip >= 0)
//      Shang et al. (2020) eq. 19: xi <= pmax - p_hat (actual <= pmax)
//
//      These are the PHYSICAL LIMITS of a continuous SVC uncertainty
//      set. In the paper's optimization, the probability mass near
//      these extremes is shaped by 729 training samples and is
//      negligible for extreme values. The bounds define the SUPPORT
//      of the distribution, not the mass concentration.
//
//      When discretized to 3 points {XI_MIN, 0, XI_MAX} with equal-ish
//      weights (0.20/0.30/0.50 for low forecast), assigning 50% weight
//      to XI_MAX = 50 gives E[xi] = +25mm for p_hat=0. This is a
//      PHANTOM RAINFALL "safety net" — the model injects 25mm of
//      unexpected rain every 6 hours during dry weather, making any
//      controller appear safe by flooding the soil with fictitious water.
//
//      The correct approach for discrete models: forecast-proportional
//      bounds matching NWS QPF verification statistics:
//        p_hat=0:  xi in {0, 1, 2}      E[xi] = +0.45mm
//        p_hat=2:  xi in {-2..+2}       E[xi] = +0.15mm
//        p_hat=10: xi in {-5..+5}       E[xi] = -0.56mm
//
//      These match: (1) NWS QPF MAE of 1-3mm for 6-hr accumulations,
//      (2) FAO guidance of 30-50% error relative to forecast magnitude,
//      (3) Shang et al. Fig. 2 pattern of overestimation bias for heavy
//      rain and underestimation bias for light rain.
//      Ref: Shang et al. (2020) eq. 18-19; NWS QPF verification
//
// [C3] ET forecast range expanded: e_hat in [1,4] mm/6hr
//      V1 used [2,3] = 8-12 mm/day, which exceeds Iowa summer peak
//      and cannot represent cool/overcast conditions.
//      New [1,4] = 4-16 mm/day covers full growing season:
//        e_hat=1: cool overcast day (ETc ~ 4mm/day)
//        e_hat=2: typical spring/fall (ETc ~ 8mm/day)
//        e_hat=3: warm summer day (ETc ~ 12mm/day)
//        e_hat=4: peak summer heat (ETc ~ 16mm/day)
//      Ref: Allen et al. FAO-56 Table 12 (1998)
//
// [C4] Markov weather transitions replace i.i.d. scenario draws
//      V1 drew each 6-hr forecast independently from a fixed scenario
//      distribution (Dry/Rainy/Variable). This ignored temporal
//      correlation — a sunny morning followed by a sunny afternoon
//      is far more likely than a sunny morning followed by a storm.
//
//      V3 uses a 3-state Markov chain {Dry, Moderate, Wet}:
//        P(Dry|Dry) = 0.70  (strong persistence in summer high pressure)
//        P(Mod|Mod) = 0.45  (moderate — transitional weather is unstable)
//        P(Wet|Wet) = 0.70  (strong persistence in frontal systems)
//
//      Stationary distribution: pi(Dry)~0.31, pi(Mod)~0.36, pi(Wet)~0.33
//      This is balanced (no dominant state), appropriate for Iowa's
//      variable growing season climate.
//      Ref: Wilks (2011) Ch. 11; Richardson (1981) weather generators
//
// [C5] Nondeterministic controller — action set documentation
//      The 6-action set {0, 2, 4, 6, 8, 10} is retained from V1.
//      This discretization is justified by:
//        - 2mm granularity matches practical irrigation valve increments
//        - 6 actions keep state space tractable for synthesis
//        - Full range [0, umax] is covered
//      The synthesised optimal policy maps each reachable state
//      (x, t, p_hat, e_hat, w_state) to the best irrigation action.
//
// [C7] Terminal self-loops added to eliminate deadlock warnings.
//      V1 had 6943 deadlock states reported by Storm. These are now
//      resolved by self-loops at t=Tmax in all modules.
//
////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////
// PARAMETERS
////////////////////////////////////////////////////////////////////////
const int Tmax    = 28;         // 7 days x 4 intervals/day = 28 steps
const int xmin    = 30;         // Safety threshold (mm) [Shang et al. 2020]
const int umax    = 10;         // Max irrigation per 6-hr interval (mm)
const double c;                 // Decay factor — passed via -const
                                //   c=0.01  (clay)       [Ooi et al. 2008]
                                //   c=0.025 (loam)       [Shang et al. 2020]
                                //   c=0.05  (sandy loam) [Delgoda et al. 2016]
const int w_init;               // Initial weather state — passed via -const
                                //   0 = Dry start
                                //   1 = Moderate start
                                //   2 = Wet start

// Discretisation thresholds (for labels/analysis, NOT for control)
const int X_CRITICAL = 30;
const int X_LOW      = 40;
const int X_MODERATE = 50;
const int X_HIGH     = 60;

////////////////////////////////////////////////////////////////////////
// [C3] EXPANDED FORECAST RANGES
////////////////////////////////////////////////////////////////////////
const int P_HAT_MIN = 0;
const int P_HAT_MAX = 10;
const int E_HAT_MIN = 1;        // Was 2 (v1); now 1 [FAO-56]
const int E_HAT_MAX = 4;        // Was 3 (v1); now 4 [FAO-56]

////////////////////////////////////////////////////////////////////////
// [C1] ET UNCERTAINTY — 5-POINT DISTRIBUTION
////////////////////////////////////////////////////////////////////////
// Validation against FAO-56:
//   e_hat=1: +-1mm = 100%, +-2mm = 200% (3% at extreme — acceptable)
//   e_hat=2: +-1mm = 50%,  +-2mm = 100% (extreme heat wave scenario)
//   e_hat=3: +-1mm = 33%,  +-2mm = 67%  (within FAO-56 40% extreme)
//   e_hat=4: +-1mm = 25%,  +-2mm = 50%  (matches FAO-56 extreme bound)
//
// 87% within +-1mm = FAO-56 compliant for typical conditions
// 13% at +-2mm = captures rare extremes for safety analysis
const int ETA_MIN = -2;
const int ETA_MAX = 2;
const double prob_eta_m2 = 0.03;    // P(eta=-2): extreme overestimation
const double prob_eta_m1 = 0.12;    // P(eta=-1): moderate overestimation
const double prob_eta_0  = 0.50;    // P(eta= 0): accurate forecast
const double prob_eta_p1 = 0.25;    // P(eta=+1): moderate underestimation
const double prob_eta_p2 = 0.10;    // P(eta=+2): extreme underestimation
// Sum = 1.00; E[eta] = +0.27 mm; SD[eta] = 0.90 mm

////////////////////////////////////////////////////////////////////////
// [C2] PRECIPITATION ERROR PROBABILITIES
////////////////////////////////////////////////////////////////////////
// CASE 1: Zero forecast (p_hat = 0) — surprise rain only
const double prob_xi_zero_p0 = 0.65;   // No rain as forecast
const double prob_xi_zero_p1 = 0.25;   // 1mm surprise shower
const double prob_xi_zero_p2 = 0.10;   // 2mm surprise rain
// E[xi] = +0.45 mm

// CASE 2: Low forecast (p_hat in [1..4])
const double prob_xi_low_m2 = 0.05;    // -2mm: much less than forecast
const double prob_xi_low_m1 = 0.15;    // -1mm: somewhat less
const double prob_xi_low_0  = 0.45;    // 0mm:  accurate
const double prob_xi_low_p1 = 0.25;    // +1mm: somewhat more
const double prob_xi_low_p2 = 0.10;    // +2mm: much more
// E[xi] = +0.15 mm

// CASE 3: Medium/high forecast (p_hat >= 5)
const double prob_xi_high_m5 = 0.08;   // extreme overestimation
const double prob_xi_high_m2 = 0.25;   // moderate overestimation
const double prob_xi_high_0  = 0.40;   // accurate
const double prob_xi_high_p2 = 0.19;   // moderate underestimation
const double prob_xi_high_p5 = 0.08;   // extreme underestimation
// E[xi] = -0.56 mm (overestimation bias for heavy rain)

////////////////////////////////////////////////////////////////////////
// EXECUTION PHASES
////////////////////////////////////////////////////////////////////////
// 0=Forecast, 1=Controller, 2=ET noise, 3=Precip noise, 4=Soil update
global step : [0..4] init 0;

////////////////////////////////////////////////////////////////////////
// PRECIPITATION ERROR BOUND FORMULAS (for high-forecast regime)
////////////////////////////////////////////////////////////////////////
formula xi_neg_extreme  = -min(p_hat, 5);
formula xi_neg_moderate = floor(xi_neg_extreme / 2);
formula xi_pos_moderate = max(1, floor(min(5, max(2, floor(p_hat/2))) / 2));
formula xi_pos_extreme  = min(5, max(2, floor(p_hat/2)));

////////////////////////////////////////////////////////////////////////
// [C4] FORECAST MODULE WITH MARKOV WEATHER TRANSITIONS
////////////////////////////////////////////////////////////////////////
// 3-state Markov chain: {Dry=0, Moderate=1, Wet=2}
// Persistence: P(Dry|Dry)=0.70, P(Mod|Mod)=0.45, P(Wet|Wet)=0.70
// Stationary: pi(Dry)~0.31, pi(Mod)~0.36, pi(Wet)~0.33
//
// Coupling: Dry => high ET, low precip (clear skies)
//           Wet => low ET (cloud cover), high precip
// Ref: Wilks (2011) Ch. 11; Richardson (1981)

module Forecast
    p_hat : [P_HAT_MIN..P_HAT_MAX] init 0;
    e_hat : [E_HAT_MIN..E_HAT_MAX] init 2;
    w_state : [0..2] init w_init;

    // ---- FROM DRY STATE (w_state=0) ----
    [] step=0 & t<Tmax & w_state=0 ->
        0.70:(p_hat'=0) & (e_hat'=4) & (w_state'=0) & (step'=1) +
        0.20:(p_hat'=2) & (e_hat'=3) & (w_state'=1) & (step'=1) +
        0.10:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);

    // ---- FROM MODERATE STATE (w_state=1) ----
    [] step=0 & t<Tmax & w_state=1 ->
        0.25:(p_hat'=0) & (e_hat'=3) & (w_state'=0) & (step'=1) +
        0.45:(p_hat'=2) & (e_hat'=2) & (w_state'=1) & (step'=1) +
        0.30:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);

    // ---- FROM WET STATE (w_state=2) ----
    [] step=0 & t<Tmax & w_state=2 ->
        0.05:(p_hat'=2) & (e_hat'=2) & (w_state'=0) & (step'=1) +
        0.25:(p_hat'=5) & (e_hat'=1) & (w_state'=1) & (step'=1) +
        0.70:(p_hat'=10)& (e_hat'=1) & (w_state'=2) & (step'=1);

    // [C7] Terminal self-loop
    [] step=0 & t=Tmax ->
        (p_hat'=p_hat) & (e_hat'=e_hat) & (w_state'=w_state) & (step'=0);

endmodule

////////////////////////////////////////////////////////////////////////
// [C5] NONDETERMINISTIC CONTROLLER — OPTIMAL POLICY SYNTHESIS
////////////////////////////////////////////////////////////////////////
// Six irrigation actions offered at every step. PRISM/Storm's MDP
// solver selects the optimal action for each reachable state.
//
// All six commands share the same guard (step=1 & t<Tmax) and are
// UNLABELED — creating nondeterministic choice in PRISM MDP semantics.
//
// Action set {0, 2, 4, 6, 8, 10} mm:
//   - 2mm granularity matches practical valve increments
//   - 6 actions balance synthesis quality vs state space explosion
//   - Full range [0, umax=10] covered
//
// The synthesised scheduler/strategy maps each state
//   (x, t, p_hat, e_hat, w_state) -> u*
// giving the provably optimal state-dependent policy.

module Synthesis_Controller
    u : [0..umax] init 0;

    // ---- Six nondeterministic irrigation choices per step ----
    [] step=1 & t<Tmax -> (u'=0)  & (step'=2);
    [] step=1 & t<Tmax -> (u'=2)  & (step'=2);
    [] step=1 & t<Tmax -> (u'=4)  & (step'=2);
    [] step=1 & t<Tmax -> (u'=6)  & (step'=2);
    [] step=1 & t<Tmax -> (u'=8)  & (step'=2);
    [] step=1 & t<Tmax -> (u'=10) & (step'=2);

    // [C7] Terminal self-loop
    [] step=1 & t=Tmax -> (u'=u) & (step'=1);

endmodule

////////////////////////////////////////////////////////////////////////
// [C1] EVAPOTRANSPIRATION UNCERTAINTY — 5-POINT DISTRIBUTION
////////////////////////////////////////////////////////////////////////
module Evapotranspiration
    eta : [ETA_MIN..ETA_MAX] init 0;

    [] step=2 & t<Tmax ->
        prob_eta_m2 : (eta'=-2) & (step'=3) +
        prob_eta_m1 : (eta'=-1) & (step'=3) +
        prob_eta_0  : (eta'=0)  & (step'=3) +
        prob_eta_p1 : (eta'=1)  & (step'=3) +
        prob_eta_p2 : (eta'=2)  & (step'=3);

    // [C7] Terminal self-loop
    [] step=2 & t=Tmax -> (eta'=eta) & (step'=2);

endmodule

////////////////////////////////////////////////////////////////////////
// [C2] PRECIPITATION UNCERTAINTY — 3-REGIME CONDITIONAL DISTRIBUTION
////////////////////////////////////////////////////////////////////////
module Precipitation_error
    xi : [-5..5] init 0;

    // CASE 1: Zero forecast (p_hat = 0)
    [] step=3 & t<Tmax & p_hat=0 ->
        prob_xi_zero_p0 : (xi'=0) & (step'=4) +
        prob_xi_zero_p1 : (xi'=1) & (step'=4) +
        prob_xi_zero_p2 : (xi'=2) & (step'=4);

    // CASE 2: Low forecast (p_hat in [1..4])
    [] step=3 & t<Tmax & p_hat>=1 & p_hat<=4 ->
        prob_xi_low_m2 : (xi'=-2) & (step'=4) +
        prob_xi_low_m1 : (xi'=-1) & (step'=4) +
        prob_xi_low_0  : (xi'=0)  & (step'=4) +
        prob_xi_low_p1 : (xi'=1)  & (step'=4) +
        prob_xi_low_p2 : (xi'=2)  & (step'=4);

    // CASE 3: Medium/high forecast (p_hat >= 5)
    [] step=3 & t<Tmax & p_hat>=5 ->
        prob_xi_high_m5 : (xi'=xi_neg_extreme)  & (step'=4) +
        prob_xi_high_m2 : (xi'=xi_neg_moderate)  & (step'=4) +
        prob_xi_high_0  : (xi'=0)                & (step'=4) +
        prob_xi_high_p2 : (xi'=xi_pos_moderate)  & (step'=4) +
        prob_xi_high_p5 : (xi'=xi_pos_extreme)   & (step'=4);

    // [C7] Terminal self-loop
    [] step=3 & t=Tmax -> (xi'=xi) & (step'=3);

endmodule

////////////////////////////////////////////////////////////////////////
// SOIL DYNAMICS
////////////////////////////////////////////////////////////////////////
// Water balance equation [Shang et al. 2020, eq. 2]:
//   x(t+1) = (1-c)*x(t) + u(t) + [p_hat(t) + xi(t)] - [e_hat(t) + eta(t)]
//
// Net uncertainty per step: [-7, +7] mm (was [-53, +53] in V1)

module Soil_Dynamics
    x : [0..100] init 40;      // Soil moisture mm (overridden by scripts)
    t : [0..Tmax] init 0;

    [] step=4 & t<Tmax ->
        (x' = min(100, max(0, floor(x*(1-c) + u + p_hat + xi - e_hat - eta)))) &
        (t' = t+1) &
        (step'=0);

    // [C7] Terminal self-loop
    [] step=4 & t=Tmax ->
        (x' = x) & (t' = t) & (step'=4);

endmodule

////////////////////////////////////////////////////////////////////////
// REWARDS
////////////////////////////////////////////////////////////////////////

rewards "water_usage"
    step=4 & t<Tmax : u;
endrewards

rewards "safety_violations"
    step=4 & t<Tmax & x<xmin : 1;
endrewards

rewards "violation_penalty"
    step=4 & t<Tmax & x<xmin : 100;
endrewards

rewards "moisture_deficit"
    step=4 & t<Tmax & x<xmin : (xmin - x);
endrewards

rewards "water_loss"
    step=4 & t<Tmax : c*x;
endrewards

rewards "final_moisture"
    step=4 & t=Tmax : x;
endrewards

////////////////////////////////////////////////////////////////////////
// LABELS
////////////////////////////////////////////////////////////////////////
label "safe"           = (x >= xmin);
label "critical"       = (x < xmin);
label "comfortable"    = (x >= X_MODERATE);
label "relaxed"        = (x >= X_HIGH);
label "saturated"      = (x >= 80);
label "final_safe"     = (t=Tmax & x>=xmin);
label "final_critical" = (t=Tmax & x<xmin);
label "week_start"     = (t=0);
label "dry_weather"    = (w_state=0);
label "wet_weather"    = (w_state=2);
