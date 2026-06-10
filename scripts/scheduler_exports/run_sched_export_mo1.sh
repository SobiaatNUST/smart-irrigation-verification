#!/bin/bash
###############################################################################
# run_sched_export_mo1.sh
#
# Scheduler export for phi_mo1 at theta = 0.95  ("headline" policy).
#
# Query (exact form used in Storm):
#   multi( R{"water_usage"}min=? [C<=140], P>=0.95 [G "safe"] )
#
# Note on G "safe" vs G<=140 "safe":
#   In this setup Storm's --exportscheduler does not correctly handle the
#   bounded global operator G<=140 "safe" for multi-objective queries on
#   this model (self-loop structure interaction).  We therefore use the
#   unbounded G "safe" form here, paired with the model's terminal
#   self-loop at t=Tmax, which keeps the policy semantically equivalent
#   over the verification horizon while permitting scheduler export.
#
# Operational interpretation of the synthesised policy:
#   sigma*_{0.95} is the cheapest deterministic-on-Pareto-front controller
#   that certifies P(safe) >= 0.95 over the seven-day horizon.  Its
#   (x, w_state) -> u decision surface should look like a multi-zone
#   threshold rule whose thresholds are *model-derived* rather than
#   externally tuned -- this is what the paper's headline claim refers to.
#
# Reference cell: loam (c=0.025), Dry start (w_init=0), x(0)=40 mm.
#
# Output files:
#   Results_Sched_MO1/sched_mo1_loam_dry_x40_safe95.txt        Storm console
#   Results_Sched_MO1/sched_mo1_loam_dry_x40_safe95.scheduler  state -> action
#   Results_Sched_MO1/sched_mo1_loam_dry_x40_safe95.states     state map
#   Results_Sched_MO1/sched_mo1_loam_dry_x40_safe95.result     numeric result
#   Results_Sched_MO1/sched_mo1_loam_dry_x40_safe95.props      property used
#   Logs_Sched_MO1/sched_mo1_loam_dry_x40_safe95.log           Storm stderr
#
# Wall:    ~1.5--3 h (1.6e7 reachable states, 6.5e7 transitions)
# Timeout: 7200 s (2 h) hard limit; override with --timeout
#
# Usage:
#   chmod +x run_sched_export_mo1.sh
#   ./run_sched_export_mo1.sh --storm /path/to/storm/build/bin/storm
#   ./run_sched_export_mo1.sh --storm /path/to/storm --force
###############################################################################

set -euo pipefail

# ======================== CONFIGURATION ======================================

STORM_BIN="/path/to/storm/build/bin/storm"
MODEL_FILE="../../models/M3/M3_mdp_synthesis.pm"
STORM_ENGINE="sparse"

RESULTS_DIR="Results_Sched_MO1"
LOG_DIR="Logs_Sched_MO1"

# Reference cell + property threshold
C_REF="0.025"
W_INIT_REF="0"
XINIT="40"
THETA="0.95"
SCENARIO="sched_mo1_loam_dry_x${XINIT}_safe95"

# Multi-objective precision & iteration cap
MO_PRECISION="1e-4"
MO_MAXSTEPS="10000"

# Hard timeout (seconds); 7200 = 2 h
TIMEOUT_SECS=7200

# Resume mode default
RESUME=1
FORCE=0

# ======================== COLOURS ============================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_skip()  { echo -e "${CYAN}[SKIP]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

# ======================== CLI ================================================
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --storm PATH    Path to storm binary  (default: $STORM_BIN)
  --model FILE    Path to PRISM model   (default: $MODEL_FILE)
  --xinit N       Initial soil moisture (default: $XINIT)
  --theta T       Safety threshold      (default: $THETA)
  --timeout S     Hard timeout seconds  (default: $TIMEOUT_SECS)
  --resume        (default) Skip if all output files are already complete
  --force         Re-run and overwrite prior outputs
  --help|-h       Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --storm)   STORM_BIN="$2";    shift 2 ;;
        --model)   MODEL_FILE="$2";   shift 2 ;;
        --xinit)   XINIT="$2";        shift 2 ;;
        --theta)   THETA="$2";        shift 2 ;;
        --timeout) TIMEOUT_SECS="$2"; shift 2 ;;
        --resume)  RESUME=1; FORCE=0; shift ;;
        --force)   FORCE=1; RESUME=0; shift ;;
        --help|-h) usage; exit 0 ;;
        *) log_error "Unknown argument: $1"; usage; exit 1 ;;
    esac
done

SCENARIO="sched_mo1_loam_dry_x${XINIT}_safe$(echo "$THETA" | tr -d '.')"

# ======================== PATHS ==============================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
mkdir -p "$PROJECT_DIR/$RESULTS_DIR" "$PROJECT_DIR/$LOG_DIR"

if [[ "$MODEL_FILE" != /* ]]; then
    MODEL_FILE_ABS="$( cd "$SCRIPT_DIR" && cd "$( dirname "$MODEL_FILE" )" && pwd )/$( basename "$MODEL_FILE" )"
else
    MODEL_FILE_ABS="$MODEL_FILE"
fi

RESULT_TXT="$PROJECT_DIR/$RESULTS_DIR/${SCENARIO}.txt"
LOG_FILE="$PROJECT_DIR/$LOG_DIR/${SCENARIO}.log"
SCHED_FILE="$PROJECT_DIR/$RESULTS_DIR/${SCENARIO}.scheduler"
STATES_FILE="$PROJECT_DIR/$RESULTS_DIR/${SCENARIO}.states"
RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${SCENARIO}.result"
PROP_FILE="$PROJECT_DIR/$RESULTS_DIR/${SCENARIO}.props"
TEMP_MODEL="$PROJECT_DIR/${SCENARIO}_temp.pm"

# ======================== CLEANUP TRAP =======================================
cleanup() {
    local exit_code=$?
    rm -f "$TEMP_MODEL"
    [[ ${PROP_WRITTEN:-0} -eq 1 && $exit_code -ne 0 ]] && rm -f "$PROP_FILE"
    if [[ $exit_code -eq 130 ]]; then
        echo ""
        log_warn "Run interrupted by user (SIGINT). Temp files cleaned up."
    fi
    exit $exit_code
}
trap cleanup INT TERM EXIT

# ======================== PRE-FLIGHT =========================================
[[ -f "$MODEL_FILE_ABS" ]] || { log_error "Model not found: $MODEL_FILE_ABS"; exit 1; }
[[ -x "$STORM_BIN" ]] || {
    log_error "Storm not executable: $STORM_BIN"
    echo "  Pass:  $0 --storm /path/to/storm/build/bin/storm"
    exit 1
}

STORM_VER=$("$STORM_BIN" --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
STORM_MAJOR=$(echo "$STORM_VER" | cut -d. -f1)
STORM_MINOR=$(echo "$STORM_VER" | cut -d. -f2)
if [[ "$STORM_VER" != "unknown" ]] \
    && (( STORM_MAJOR < 1 || ( STORM_MAJOR == 1 && STORM_MINOR < 7 ) )); then
    log_warn "Storm $STORM_VER detected. >= 1.7 recommended for multi-obj scheduler export."
fi

if ! [[ "$XINIT" =~ ^[0-9]+$ ]] || (( XINIT < 0 || XINIT > 100 )); then
    log_error "XINIT must be an integer in [0,100]; got: $XINIT"; exit 1
fi

FREE_KB=$(df -k "$PROJECT_DIR" | awk 'NR==2 {print $4}')
if (( FREE_KB < 2097152 )); then
    log_warn "Low disk space: $(( FREE_KB / 1024 )) MB free"
fi

# ======================== HEADER =============================================
echo ""
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo -e "${BOLD}${GREEN}  MO1 scheduler export: sigma*_${THETA}  (headline policy)  ${NC}"
echo -e "${BOLD}${GREEN}  Cell: loam (c=${C_REF}), Dry (w_init=${W_INIT_REF}), x=${XINIT}${NC}"
echo -e "${BOLD}${GREEN}  Query family: multi( R^w_min=?,  P>=${THETA} [G safe] )    ${NC}"
echo -e "${BOLD}${GREEN}============================================================${NC}"
echo ""
echo -e "  Storm:     ${CYAN}$STORM_VER${NC}  ($STORM_BIN)"
echo -e "  Model:     $MODEL_FILE_ABS"
echo -e "  Engine:    $STORM_ENGINE"
echo -e "  Precision: $MO_PRECISION   Max steps: $MO_MAXSTEPS"
echo -e "  Timeout:   ${TIMEOUT_SECS}s"
echo ""

# ======================== RESUME CHECK =======================================
is_complete() {
    [[ -f "$RESULT_TXT"   ]] \
        && grep -q "Result (for initial states):" "$RESULT_TXT" \
        && [[ -s "$SCHED_FILE"  ]] \
        && [[ -s "$STATES_FILE" ]] \
        && [[ -s "$RESULT_FILE" ]]
}

if [[ $RESUME -eq 1 && $FORCE -eq 0 ]] && is_complete; then
    value=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' "$RESULT_TXT" | head -1 || echo "N/A")
    sched_lines=$(wc -l < "$SCHED_FILE")
    states_lines=$(wc -l < "$STATES_FILE")
    log_skip "Synthesis already complete -- nothing to do."
    echo ""
    echo -e "  result (min water) = ${BOLD}${value}${NC} mm"
    echo -e "  Scheduler:  ${CYAN}${SCHED_FILE}${NC} (${sched_lines} lines)"
    echo -e "  States:     ${CYAN}${STATES_FILE}${NC} (${states_lines} lines)"
    echo "  Use --force to re-run regardless."
    exit 0
fi

# ======================== PATCH XINIT ========================================
sed "s/x : \[0\.\.100\] init [0-9]\+/x : [0..100] init $XINIT/" \
    "$MODEL_FILE_ABS" > "$TEMP_MODEL"
grep -q "x : \[0\.\.100\] init $XINIT" "$TEMP_MODEL" || {
    log_error "sed patch failed -- could not set xinit=$XINIT"; exit 1; }
log_info "Model patched: x init = $XINIT"

# ======================== WRITE PROPERTY FILE ================================
# We intentionally use the UNBOUNDED G "safe" because Storm's
# --exportscheduler does not handle G<=140 "safe" correctly in this setup.
# The model's terminal self-loop at t=Tmax preserves safety semantics over
# the verification horizon.
cat > "$PROP_FILE" <<EOF
multi( R{"water_usage"}min=? [C<=140], P>=${THETA} [G "safe"] )
EOF
PROP_WRITTEN=1
log_info "Property file written: $PROP_FILE"
echo -e "  Query: $(cat "$PROP_FILE")"
echo ""

# ======================== RUN STORM ==========================================
log_warn "Starting synthesis (~1.5--3 h expected; hard timeout ${TIMEOUT_SECS}s)..."
echo ""
start_ts=$(date +%s)

STORM_EXIT=0
timeout "$TIMEOUT_SECS" "$STORM_BIN" \
    --prism        "$TEMP_MODEL"  \
    --propfile     "$PROP_FILE"   \
    --constants    "c=$C_REF,w_init=$W_INIT_REF" \
    --engine       "$STORM_ENGINE" \
    --prismcompat  \
    --statistics   \
    --multiobjective:precision "$MO_PRECISION" \
    --multiobjective:maxsteps  "$MO_MAXSTEPS"  \
    --exportscheduler "$SCHED_FILE"  \
    --exportstates    "$STATES_FILE" \
    --exportresult    "$RESULT_FILE" \
    > "$RESULT_TXT" 2> "$LOG_FILE" || STORM_EXIT=$?

end_ts=$(date +%s)
wall=$(( end_ts - start_ts ))
wall_fmt="$(( wall / 60 ))m $(( wall % 60 ))s"

# ======================== TIMEOUT ============================================
if [[ $STORM_EXIT -eq 124 ]]; then
    log_fail "Storm timed out after ${TIMEOUT_SECS}s"
    echo "  Try increasing --timeout or relaxing --multiobjective:precision"
    exit 1
fi

# ======================== SUCCESS ============================================
if [[ $STORM_EXIT -eq 0 ]]; then
    value=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' "$RESULT_TXT" | head -1 || echo "N/A")
    log_ok "Storm finished in ${wall_fmt}"
    echo ""
    echo -e "  result (min water) = ${BOLD}${value}${NC} mm"

    if [[ ! -s "$SCHED_FILE" ]]; then
        log_warn "Scheduler file is EMPTY (multi-obj export may be unsupported)."
        echo "  Try stormpy Python API or upgrade Storm to >= 1.7."
    else
        sched_lines=$(wc -l < "$SCHED_FILE")
        states_lines=$(wc -l < "$STATES_FILE")
        log_ok "Scheduler: ${sched_lines} states  |  States file: ${states_lines} lines"
        echo ""
        echo -e "  ${BOLD}Scheduler preview (first 3 lines):${NC}"
        head -3 "$SCHED_FILE" | sed 's/^/    /'
    fi

    WARNS=$(grep -ci "warn\|unsupported\|not supported\|skipping" "$LOG_FILE" 2>/dev/null || true)
    if (( WARNS > 0 )); then
        log_warn "${WARNS} warning(s) in Storm log:"
        grep -i "warn\|unsupported\|not supported\|skipping" "$LOG_FILE" | head -5 | sed 's/^/  /'
    fi

    echo ""
    echo "Next: python3 parse_G3_scheduler.py --states <.states> --scheduler <.scheduler>"
    exit 0
fi

# ======================== FAILURE ============================================
log_fail "Storm exited with code ${STORM_EXIT}  (wall: ${wall_fmt})"
echo ""
echo "Last 10 lines of $LOG_FILE:"
tail -10 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
exit 1
