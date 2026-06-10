mdp

////////////////////////////////////////////////////////////////////////
// THRESHOLD-BASED HEURISTIC IRRIGATION CONTROLLER — VERSION 3
////////////////////////////////////////////////////////////////////////
//
// OVERVIEW:
// This model implements a state-dependent, threshold-based heuristic
// controller that approximates MPC behavior using moisture-zone rules.
// It is NOT an ON-OFF controller (Shang et al. eq. 47) nor a full MPC.
// Instead, it uses 5 operating modes with forecast-reactive irrigation
// amounts, giving a practical middle ground.
//
// CHANGES FROM VERSION 1 (M2_RuleBased_Uncertainty_V1):
//
// [C1] ET uncertainty: 5-point distribution eta in {-2,-1,0,+1,+2} mm
//      Old: {-3,0,+3} = +-100-150% of e_hat. FAO-56 says 10-20%.
//      New: {-2..+2} with 87% of mass within +-1mm.
//      Justification: Hargreaves-Samani RMSE ~ 0.5-1.5 mm/day
//      Ref: Allen et al. FAO-56 (1998); Hargreaves & Samani (1985)
//
// [C2] Precipitation uncertainty: 3-regime FORECAST-PROPORTIONAL bounds
//      Old: XI_MAX = 50-p_hat gave E[xi]=+25mm when p_hat=0 (absurd).
//      New: Errors scale with forecast magnitude (~30-50% of p_hat).
//      Ref: Shang et al. (2020) eq. 18-19; NWS QPF verification
//
// [C3] ET forecast range expanded: e_hat in [1,4] mm/6hr
//      Old: [2,3] = 8-12 mm/day (too narrow for full growing season).
//      New: [1,4] = 4-16 mm/day covers Iowa growing season ETc range.
//      Ref: Allen et al. FAO-56 Table 12 (1998)
//
// [C4] Markov weather transitions replace i.i.d. scenario draws
//      Old: Each 6-hr interval independently drawn from scenario dist.
//      New: 3-state Markov chain {Dry, Moderate, Wet} with persistence.
//      Ref: Wilks (2011) Ch. 11; Richardson (1981) weather generators
//
// [C5] Controller renamed from "Rule-Based" to "Threshold-Based Heuristic"
//      The V1 name implied an ON-OFF controller (Shang et al. eq. 47).
//      This controller uses 5 moisture zones with forecast-reactive
//      irrigation amounts — a heuristic approximation of MPC, not a
//      simple ON-OFF rule. Renamed for clarity and academic accuracy.
//      Controller guards updated for expanded e_hat range [1,4].
//
// [C7] Terminal self-loops in all modules to eliminate deadlock warnings.
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

// Moisture zone thresholds for controller modes [Shang et al. 2020, Sec. IV]
const int X_CRITICAL = 30;      // Below: Emergency mode (= xmin)
const int X_LOW      = 40;      // Below: Conservative mode
const int X_MODERATE = 50;      // Below: Moderate mode
const int X_HIGH     = 60;      // Above: Relaxed mode

////////////////////////////////////////////////////////////////////////
// [C3] EXPANDED FORECAST RANGES
////////////////////////////////////////////////////////////////////////
// ET forecast: FAO-56 ET0 for Iowa growing season = 3-8 mm/day
// With crop coefficient Kc = 0.8-1.2 (Allen et al. 1998, Table 12):
//   ETc = 2.4-9.6 mm/day => 0.6-2.4 mm/6hr => integers [1,4]
// Precipitation forecast: 6-hr cumulative QPF [Iowa State Meteogram]
//   Range 0-10mm covers ~95% of 6-hr precipitation events in Iowa
const int P_HAT_MIN = 0;
const int P_HAT_MAX = 10;
const int E_HAT_MIN = 1;        // Was 2 (v1); now 1 [FAO-56 justified]
const int E_HAT_MAX = 4;        // Was 3 (v1); now 4 [FAO-56 justified]

////////////////////////////////////////////////////////////////////////
// [C1] ET UNCERTAINTY — REDUCED AND REFINED
////////////////////////////////////////////////////////////////////////
// Literature basis:
//   Hargreaves-Samani (1985): RMSE = 0.5-1.5 mm/DAY for daily ET
//   FAO-56 (Allen et al. 1998): 10-20% error under standard conditions
//
// Decision: eta in [-2, +2] mm
//   Core mass (87%) within [-1, +1] => FAO-56 compliant for all e_hat
//   Tails at +-2mm (13%) capture rare extremes
//   Asymmetric positive skew: ET models underpredict in summer
//   E[eta] = +0.27 mm; SD[eta] = 0.90 mm
const int ETA_MIN = -2;
const int ETA_MAX = 2;
const double prob_eta_m2 = 0.03;    // P(eta=-2): extreme overestimation
const double prob_eta_m1 = 0.12;    // P(eta=-1): moderate overestimation
const double prob_eta_0  = 0.50;    // P(eta= 0): accurate forecast
const double prob_eta_p1 = 0.25;    // P(eta=+1): moderate underestimation
const double prob_eta_p2 = 0.10;    // P(eta=+2): extreme underestimation
// Sum = 1.00; E[eta] = +0.27 mm

////////////////////////////////////////////////////////////////////////
// [C2] PRECIPITATION ERROR PROBABILITIES — CONDITIONAL ON FORECAST
////////////////////////////////////////////////////////////////////////
// Literature basis:
//   NWS QPF verification (6-hr, warm season): MAE ~ 1-3mm, RMSE ~ 2-5mm
//   FAO guidelines: 30-50% of forecast magnitude for <48hr forecasts
//   Shang et al. (2020) eq.18-19: physical limits, not discrete bounds
//
// Three regimes based on forecast magnitude:

// CASE 1: Zero forecast (p_hat = 0) — surprise rain only
// Iowa warm season: ~25-35% of dry-forecast windows get measurable precip
// E[xi] = +0.45 mm
const double prob_xi_zero_p0 = 0.65;   // No rain as forecast
const double prob_xi_zero_p1 = 0.25;   // 1mm surprise shower
const double prob_xi_zero_p2 = 0.10;   // 2mm surprise rain

// CASE 2: Low forecast (p_hat in [1..4]) — +-2mm errors
// NWS MAE for light rain: 1-2mm; slight positive bias
// E[xi] = +0.15 mm
const double prob_xi_low_m2 = 0.05;    // -2mm: much less than forecast
const double prob_xi_low_m1 = 0.15;    // -1mm: somewhat less
const double prob_xi_low_0  = 0.45;    // 0mm:  accurate
const double prob_xi_low_p1 = 0.25;    // +1mm: somewhat more
const double prob_xi_low_p2 = 0.10;    // +2mm: much more than forecast

// CASE 3: Medium/high forecast (p_hat >= 5) — scaled errors
// NWS MAE for moderate/heavy rain: 2-5mm; overestimation bias
// E[xi] = -0.56 mm
const double prob_xi_high_m5 = 0.08;   // extreme overestimation
const double prob_xi_high_m2 = 0.25;   // moderate overestimation
const double prob_xi_high_0  = 0.40;   // accurate
const double prob_xi_high_p2 = 0.19;   // moderate underestimation
const double prob_xi_high_p5 = 0.08;   // extreme underestimation

////////////////////////////////////////////////////////////////////////
// EXECUTION PHASES AND STATE
////////////////////////////////////////////////////////////////////////
// 0=Forecast, 1=Controller, 2=ET noise, 3=Precip noise, 4=Soil update
global step : [0..4] init 0;

////////////////////////////////////////////////////////////////////////
// PRECIPITATION ERROR BOUND FORMULAS (for high-forecast regime)
////////////////////////////////////////////////////////////////////////
// Error magnitude scales with p_hat for moderate/heavy rain:
//   Negative extreme: -min(p_hat, 5)  [physical: actual >= 0]
//   Positive extreme: +min(5, max(2, floor(p_hat/2)))
//   Intermediates: half of extremes
formula xi_neg_extreme  = -min(p_hat, 5);
formula xi_neg_moderate = floor(xi_neg_extreme / 2);
formula xi_pos_moderate = max(1, floor(min(5, max(2, floor(p_hat/2))) / 2));
formula xi_pos_extreme  = min(5, max(2, floor(p_hat/2)));

////////////////////////////////////////////////////////////////////////
// HELPER FORMULAS FOR CONTROLLER LOGIC
////////////////////////////////////////////////////////////////////////
// Net water deficit: positive = drying conditions (ET exceeds precip)
// Used by controller to assess forecast conditions
formula net_deficit = e_hat - p_hat;

////////////////////////////////////////////////////////////////////////
// [C4] FORECAST MODULE WITH MARKOV WEATHER TRANSITIONS
////////////////////////////////////////////////////////////////////////
// 3-state Markov chain: {Dry=0, Moderate=1, Wet=2}
// Persistence: P(Dry|Dry)=0.70, P(Mod|Mod)=0.45, P(Wet|Wet)=0.70
// Stationary: pi(Dry)~0.31, pi(Mod)~0.36, pi(Wet)~0.33
// Lag-1 autocorrelation: ~0.5-0.7 (6hr weather persistence)
//
// Coupling: Dry => high ET, low precip (clear skies)
//           Wet => low ET (cloud cover), high precip
// Ref: Wilks (2011) Ch. 11; Richardson (1981) weather generators

module Forecast
    p_hat : [P_HAT_MIN..P_HAT_MAX] init 0;
    e_hat : [E_HAT_MIN..E_HAT_MAX] init 2;
    w_state : [0..2] init w_init;

    // weather state evolves as Markov chain based on current conditions

    // ---- FROM DRY STATE (w_state=0) ----
    // Clear skies: high ET (e_hat=3-4), no or little precipitation
    // 70% persistence: strong dry spells typical in Iowa summer
    [] step=0 & t<Tmax & w_state=0 ->
        0.70:(p_hat'=0) & (e_hat'=4) & (w_state'=0) & (step'=1) +
        0.20:(p_hat'=2) & (e_hat'=3) & (w_state'=1) & (step'=1) +
        0.10:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);

    // ---- FROM MODERATE STATE (w_state=1) ----
    // Partly cloudy / light rain: moderate ET, light precipitation
    [] step=0 & t<Tmax & w_state=1 ->
        0.25:(p_hat'=0) & (e_hat'=3) & (w_state'=0) & (step'=1) +
        0.45:(p_hat'=2) & (e_hat'=2) & (w_state'=1) & (step'=1) +
        0.30:(p_hat'=5) & (e_hat'=2) & (w_state'=2) & (step'=1);

    // ---- FROM WET STATE (w_state=2) ----
    // Overcast/rainy: low ET (cloud cover reduces solar radiation),
    // heavy precipitation with 70% persistence (frontal systems)
    [] step=0 & t<Tmax & w_state=2 ->
        0.05:(p_hat'=2) & (e_hat'=2) & (w_state'=0) & (step'=1) +
        0.25:(p_hat'=5) & (e_hat'=1) & (w_state'=1) & (step'=1) +
        0.70:(p_hat'=10)& (e_hat'=1) & (w_state'=2) & (step'=1);

    // [C7] Terminal self-loop: absorb at t=Tmax
    [] step=0 & t=Tmax ->
        (p_hat'=p_hat) & (e_hat'=e_hat) & (w_state'=w_state) & (step'=0);

endmodule

////////////////////////////////////////////////////////////////////////
// [C5] THRESHOLD-BASED HEURISTIC CONTROLLER
////////////////////////////////////////////////////////////////////////
// 5 operating modes based on soil moisture zones:
//
// MODE 1 — EMERGENCY (x < 30mm):
//   Maximum irrigation regardless of forecast. Soil is at or below
//   safety threshold; any further drying risks crop damage.
//   Ref: Shang et al. (2020) Sec. IV: "when x drops below xmin,
//   the system enters a critical state requiring immediate action"
//
// MODE 2 — CONSERVATIVE (30 <= x < 40mm):
//   High irrigation with forecast modulation. Moisture is above
//   threshold but buffer is thin. Dry forecasts trigger near-max
//   irrigation; rainy forecasts allow slight reduction.
//
// MODE 3 — MODERATE (40 <= x < 50mm):
//   Forecast-reactive irrigation. Enough buffer to respond to
//   weather signals. No rain → significant irrigation;
//   heavy rain → minimal supplement.
//
// MODE 4 — COMFORTABLE (50 <= x < 60mm):
//   Conservation-focused. Rain forecast → zero irrigation.
//   Dry + high ET → light irrigation. Dry + low ET → minimal.
//
// MODE 5 — RELAXED (x >= 60mm):
//   Minimal irrigation. Only act if extremely dry and hot forecast.
//   Otherwise, let natural precipitation and existing buffer suffice.
//
// Guards are mutually exclusive and exhaustive within each zone.
// Controller is DETERMINISTIC (no nondeterministic choices).
// [C5] Updated for e_hat in [1,4] (was [2,3] in V1).

module ThresholdBased_Controller
    u : [0..umax] init 0;

    // ============================================================
    // MODE 1: EMERGENCY — x < X_CRITICAL (30mm)
    // ============================================================
    // Maximum irrigation, no questions asked
    [] step=1 & x < X_CRITICAL & t<Tmax ->
        (u'=umax) & (step'=2);

    // ============================================================
    // MODE 2: CONSERVATIVE — X_CRITICAL <= x < X_LOW (30-40mm)
    // ============================================================
    // Thin buffer above safety; irrigate heavily but modulate by forecast
    //
    // Dry conditions (low rain forecast): u = 8mm
    //   With p_hat < 5, expected precip contribution is small.
    //   At x=30, worst case: x_next = 30*0.975 + 8 + 0 - 4 - 2 = 31.25mm
    //   (barely safe with max ET + error, needs strong irrigation)
    [] step=1 & x>=X_CRITICAL & x<X_LOW & p_hat<5 & t<Tmax ->
        (u'=8) & (step'=2);

    // Wet conditions (rain forecast >= 5mm): u = 5mm
    //   Expected precip helps, but moisture is still low; maintain buffer
    [] step=1 & x>=X_CRITICAL & x<X_LOW & p_hat>=5 & t<Tmax ->
        (u'=5) & (step'=2);

    // ============================================================
    // MODE 3: MODERATE — X_LOW <= x < X_MODERATE (40-50mm)
    // ============================================================
    // Enough buffer for forecast-reactive control
    //
    // No rain + high ET (e_hat >= 3): u = 7mm
    //   Drying pressure is high; needs substantial irrigation
    [] step=1 & x>=X_LOW & x<X_MODERATE & p_hat=0 & e_hat>=3 & t<Tmax ->
        (u'=7) & (step'=2);

    // No rain + low ET (e_hat <= 2): u = 5mm
    //   Drying pressure is moderate; less irrigation needed
    [] step=1 & x>=X_LOW & x<X_MODERATE & p_hat=0 & e_hat<=2 & t<Tmax ->
        (u'=5) & (step'=2);

    // Light rain (1 <= p_hat <= 4): u = 4mm
    //   Some precipitation expected; supplement moderately
    [] step=1 & x>=X_LOW & x<X_MODERATE & p_hat>=1 & p_hat<=4 & t<Tmax ->
        (u'=4) & (step'=2);

    // Heavy rain (p_hat >= 5): u = 2mm
    //   Good rain expected; only minimal supplement
    [] step=1 & x>=X_LOW & x<X_MODERATE & p_hat>=5 & t<Tmax ->
        (u'=2) & (step'=2);

    // ============================================================
    // MODE 4: COMFORTABLE — X_MODERATE <= x < X_HIGH (50-60mm)
    // ============================================================
    // Conservation-focused; trust forecasts
    //
    // Rain expected (p_hat >= 5): u = 0mm
    //   With good moisture and rain, no irrigation needed
    [] step=1 & x>=X_MODERATE & x<X_HIGH & p_hat>=5 & t<Tmax ->
        (u'=0) & (step'=2);

    // Dry + high ET (p_hat < 5, e_hat >= 3): u = 3mm
    //   Hot/dry conditions but comfortable moisture; light irrigation
    [] step=1 & x>=X_MODERATE & x<X_HIGH & p_hat<5 & e_hat>=3 & t<Tmax ->
        (u'=3) & (step'=2);

    // Dry + low ET (p_hat < 5, e_hat <= 2): u = 1mm
    //   Cool/dry conditions; minimal maintenance irrigation
    [] step=1 & x>=X_MODERATE & x<X_HIGH & p_hat<5 & e_hat<=2 & t<Tmax ->
        (u'=1) & (step'=2);

    // ============================================================
    // MODE 5: RELAXED — x >= X_HIGH (60mm+)
    // ============================================================
    // Minimal irrigation; large buffer protects against most scenarios
    //
    // Extremely dry + hot (p_hat = 0, e_hat >= 3): u = 2mm
    //   Only case where irrigation is warranted at high moisture
    //   At x=60, e_hat=4, eta=2: net loss = 6mm/step. Over 28 steps
    //   without rain, x could drop below 30. Small supplement helps.
    [] step=1 & x>=X_HIGH & p_hat=0 & e_hat>=3 & t<Tmax ->
        (u'=2) & (step'=2);

    // All other conditions: u = 0mm
    //   Complement of above: p_hat >= 1 OR e_hat <= 2
    //   With rain or low ET, the buffer is sufficient
    [] step=1 & x>=X_HIGH & (p_hat>=1 | e_hat<=2) & t<Tmax ->
        (u'=0) & (step'=2);

    // [C7] Terminal self-loop
    [] step=1 & t=Tmax ->
        (u' = u) & (step'=1);

endmodule

////////////////////////////////////////////////////////////////////////
// [C1] EVAPOTRANSPIRATION UNCERTAINTY — 5-POINT DISTRIBUTION
////////////////////////////////////////////////////////////////////////
// Asymmetric with positive skew (ET underestimated more in summer)
// E[eta] = +0.27mm, SD = 0.90mm
// Ref: Hargreaves-Samani (1985); Allen et al. FAO-56 (1998)

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
// Forecast-proportional error bounds with 5-point distributions.
// Three regimes: p_hat=0 (surprise rain only), p_hat in [1,4]
// (symmetric +-2mm), p_hat >= 5 (scaled, overestimation bias).
// Ref: NWS QPF verification; Shang et al. (2020) Fig. 2

module Precipitation_error
    xi : [-5..5] init 0;

    // CASE 1: Zero forecast (p_hat = 0)
    // Only non-negative errors; 3 effective points
    [] step=3 & t<Tmax & p_hat=0 ->
        prob_xi_zero_p0 : (xi'=0) & (step'=4) +
        prob_xi_zero_p1 : (xi'=1) & (step'=4) +
        prob_xi_zero_p2 : (xi'=2) & (step'=4);

    // CASE 2: Low forecast (p_hat in [1..4])
    // Symmetric range +-2mm, slight positive bias
    [] step=3 & t<Tmax & p_hat>=1 & p_hat<=4 ->
        prob_xi_low_m2 : (xi'=-2) & (step'=4) +
        prob_xi_low_m1 : (xi'=-1) & (step'=4) +
        prob_xi_low_0  : (xi'=0)  & (step'=4) +
        prob_xi_low_p1 : (xi'=1)  & (step'=4) +
        prob_xi_low_p2 : (xi'=2)  & (step'=4);

    // CASE 3: Medium/high forecast (p_hat >= 5)
    // Error bounds scale with p_hat; overestimation bias
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
// With V3 parameters, net uncertainty per step:
//   Range of (xi - eta): [-5 - 2, 5 + 2] = [-7, +7] mm
//   (Was [-53, +53] in V1 — now 7.5x tighter)
//
// floor() needed for PRISM integer state space.
// Ref: Kwiatkowska et al. (standard PRISM discrete modeling practice)

module Soil_Dynamics
    x : [0..100] init 40;      // Soil moisture mm (overridden by scripts)
    t : [0..Tmax] init 0;      // Time step counter

    // Water balance with forecast + uncertainty
    [] step=4 & t<Tmax ->
        (x' = min(100, max(0, floor(x*(1-c) + u + p_hat + xi - e_hat - eta)))) &
        (t' = t+1) &
        (step'=0);

    // [C7] Terminal self-loop: absorbing state at end of week
    [] step=4 & t=Tmax ->
        (x' = x) & (t' = t) & (step'=4);

endmodule

////////////////////////////////////////////////////////////////////////
// REWARDS
////////////////////////////////////////////////////////////////////////

// Total irrigation applied over the horizon [Shang 2020: Table I]
rewards "water_usage"
    step=4 & t<Tmax : u;
endrewards

// Count of steps below safety threshold [Shang 2020: Table III]
rewards "safety_violations"
    step=4 & t<Tmax & x<xmin : 1;
endrewards

// Heavy penalty per violation (for constrained optimisation queries)
rewards "violation_penalty"
    step=4 & t<Tmax & x<xmin : 100;
endrewards

// Magnitude of moisture shortfall below safety [Shang 2020: Sec. VI-C]
rewards "moisture_deficit"
    step=4 & t<Tmax & x<xmin : (xmin - x);
endrewards

// Water lost to runoff and deep percolation [Shang 2020: Table II]
rewards "water_loss"
    step=4 & t<Tmax : c*x;
endrewards

// Terminal moisture level (for analysis)
rewards "final_moisture"
    step=4 & t=Tmax : x;
endrewards

////////////////////////////////////////////////////////////////////////
// LABELS
////////////////////////////////////////////////////////////////////////
label "safe"           = (x >= xmin);
label "critical"       = (x < xmin);
label "comfortable"    = (x >= X_MODERATE);
label "saturated"      = (x >= 80);
label "final_safe"     = (t=Tmax & x>=xmin);
label "final_critical" = (t=Tmax & x<xmin);
label "week_start"     = (t=0);
label "dry_weather"    = (w_state=0);
label "wet_weather"    = (w_state=2);
