#!/bin/bash

#############################################
# M3 MDP Synthesis V3 — Storm Multi-Objective
# Pareto sweep for water-safety trade-offs.
#
# Two sweeps:
#   A: min water usage  s.t. P(safe) >= threshold
#   B: max P(safe)      s.t. water   <= budget
#
# Parameters:
#   c:      0.01, 0.025, 0.05
#   w_init: 0 (Dry), 1 (Moderate), 2 (Wet)
#   xinit:  20, 30, 40, 50
#############################################

set -u

# ---------------- CONFIGURATION ----------------
STORM_BIN="/path/to/storm/build/bin/storm"

MODEL_FILE="../models/M3/M3_mdp_synthesis.pm"
RESULTS_DIR="MDP_multi_obj_V3_Results"
LOG_DIR="logs_MDP_multi_v3"

STORM_ENGINE="sparse"

# ---------------- STORM WRAPPER ----------------
run_storm() {
    "$STORM_BIN" "$@"
}

# ---------------- COLOURS ----------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ---------------- PATH SETUP ----------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  M3 MDP Synthesis V3 — Multi-Objective   ${NC}"
echo -e "${GREEN}  Storm Pareto Sweep                      ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# ---------------- SANITY CHECKS ----------------
if [[ ! -f "$PROJECT_DIR/$MODEL_FILE" ]]; then
    echo -e "${RED}[ERROR] Missing model: $PROJECT_DIR/$MODEL_FILE${NC}"
    exit 1
fi

if [[ ! -x "$STORM_BIN" ]]; then
    echo -e "${RED}[ERROR] Storm binary not found: $STORM_BIN${NC}"
    exit 1
fi

echo "Testing Storm..."
STORM_VERSION_OUTPUT=$(run_storm --version 2>&1 | head -n 1 || true)
if echo "$STORM_VERSION_OUTPUT" | grep -qi "^storm"; then
    echo -e "${GREEN}[OK]${NC} Storm found: $STORM_VERSION_OUTPUT"
else
    echo -e "${RED}[ERROR]${NC} Storm test failed"
    exit 1
fi
echo ""

# ---------------- PARAMETERS ----------------
C_VALUES=(0.01 0.025 0.05)
W_INIT_VALUES=(0 1 2)
XINIT_VALUES=(20 30 40 50)

SAFETY_THRESHOLDS=(0.80 0.85 0.90 0.95 0.99)
WATER_BUDGETS=(15 20 25 30 40)

# Compute totals
TOTAL_A=0
for c in "${C_VALUES[@]}"; do for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do for t in "${SAFETY_THRESHOLDS[@]}"; do
    TOTAL_A=$((TOTAL_A + 1))
done; done; done; done

TOTAL_B=0
for c in "${C_VALUES[@]}"; do for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do for b in "${WATER_BUDGETS[@]}"; do
    TOTAL_B=$((TOTAL_B + 1))
done; done; done; done

TOTAL=$((TOTAL_A + TOTAL_B))

echo -e "${BLUE}Parameter Space:${NC}"
echo "  c values:          ${C_VALUES[*]}"
echo "  w_init values:     ${W_INIT_VALUES[*]} (0=Dry, 1=Moderate, 2=Wet)"
echo "  Initial moisture:  ${XINIT_VALUES[*]} mm"
echo "  Safety thresholds: ${SAFETY_THRESHOLDS[*]}"
echo "  Water budgets:     ${WATER_BUDGETS[*]}"
echo ""
echo "  Sweep A total: $TOTAL_A (min water | safety >= thresh)"
echo "  Sweep B total: $TOTAL_B (max safety | water <= budget)"
echo "  Grand total:   $TOTAL experiments"
echo "  Engine:        $STORM_ENGINE + --prismcompat"
echo ""
echo "  NOTE: Scheduler export not available for multi(...) properties."
echo ""
echo "Press Enter to start, or Ctrl+C to cancel..."
read -r

# ---------------- SUMMARY FILE ----------------
PARETO_SUMMARY="$PROJECT_DIR/$RESULTS_DIR/pareto_summary.csv"
echo "type,c,w_init,weather_name,xinit,threshold_or_budget,status,value,result_file" \
    > "$PARETO_SUMMARY"

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_SECONDS=$(date +%s)
CURRENT=0
SUCCESS_A=0; FAILED_A=0
SUCCESS_B=0; FAILED_B=0

# ================================================================
# SWEEP A: min water  s.t.  P(safe) >= threshold
# ================================================================
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}Sweep A: min water  s.t.  P(safe) >= threshold${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do
for thresh in "${SAFETY_THRESHOLDS[@]}"; do

    CURRENT=$((CURRENT + 1))
    case "$w" in
        0) WEATHER_NAME="Dry"      ;;
        1) WEATHER_NAME="Moderate" ;;
        2) WEATHER_NAME="Wet"      ;;
    esac

    EXP_NAME="pareto_safe_c${c}_w${w}_x${x}_t${thresh}"
    RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${EXP_NAME}_results.txt"
    LOG_FILE="$PROJECT_DIR/$LOG_DIR/${EXP_NAME}_log.txt"
    TEMP_MODEL="$PROJECT_DIR/${EXP_NAME}_temp.pm"

    sed "s/x : \[0\.\.100\] init 40/x : [0..100] init $x/" \
        "$PROJECT_DIR/$MODEL_FILE" > "$TEMP_MODEL"

    # FIX: G[<=140] instead of G<=140 (required by Storm 1.9.0)
    PROP="multi(R{\"water_usage\"}min=? [ C<=140 ], P>=${thresh} [ G[<=140] \"safe\" ])"

    echo -n "  [$CURRENT] c=$c w=$w ($WEATHER_NAME) x=$x thresh=$thresh ... "

    if run_storm \
        --prism "$TEMP_MODEL" \
        --prop  "$PROP" \
        --constants "c=$c,w_init=$w" \
        --engine "$STORM_ENGINE" \
        --prismcompat \
        > "$RESULT_FILE" 2> "$LOG_FILE"; then

        VALUE=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' \
                    "$RESULT_FILE" | head -1 || echo "N/A")
        echo -e "${GREEN}OK${NC} -> min_water = $VALUE"
        echo "min_water_safe,$c,$w,$WEATHER_NAME,$x,$thresh,SUCCESS,$VALUE,${EXP_NAME}_results.txt" \
            >> "$PARETO_SUMMARY"
        SUCCESS_A=$((SUCCESS_A + 1))
    else
        echo -e "${RED}FAILED${NC}"
        tail -3 "$LOG_FILE" | sed 's/^/    /'
        echo "min_water_safe,$c,$w,$WEATHER_NAME,$x,$thresh,FAILED,N/A,${EXP_NAME}_results.txt" \
            >> "$PARETO_SUMMARY"
        FAILED_A=$((FAILED_A + 1))
    fi

    rm -f "$TEMP_MODEL"

done; done; done; done

echo ""

# ================================================================
# SWEEP B: max P(safe)  s.t.  water <= budget
# ================================================================
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}Sweep B: max P(safe)  s.t.  water <= budget${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do
for budget in "${WATER_BUDGETS[@]}"; do

    CURRENT=$((CURRENT + 1))
    case "$w" in
        0) WEATHER_NAME="Dry"      ;;
        1) WEATHER_NAME="Moderate" ;;
        2) WEATHER_NAME="Wet"      ;;
    esac

    EXP_NAME="pareto_water_c${c}_w${w}_x${x}_b${budget}"
    RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${EXP_NAME}_results.txt"
    LOG_FILE="$PROJECT_DIR/$LOG_DIR/${EXP_NAME}_log.txt"
    TEMP_MODEL="$PROJECT_DIR/${EXP_NAME}_temp.pm"

    sed "s/x : \[0\.\.100\] init 40/x : [0..100] init $x/" \
        "$PROJECT_DIR/$MODEL_FILE" > "$TEMP_MODEL"

    # FIX: G[<=140] instead of G<=140 (required by Storm 1.9.0)
    PROP="multi(Pmax=? [ G[<=140] \"safe\" ], R{\"water_usage\"}<=${budget} [ C<=140 ])"

    echo -n "  [$CURRENT] c=$c w=$w ($WEATHER_NAME) x=$x budget=$budget ... "

    if run_storm \
        --prism "$TEMP_MODEL" \
        --prop  "$PROP" \
        --constants "c=$c,w_init=$w" \
        --engine "$STORM_ENGINE" \
        --prismcompat \
        > "$RESULT_FILE" 2> "$LOG_FILE"; then

        VALUE=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' \
                    "$RESULT_FILE" | head -1 || echo "N/A")
        echo -e "${GREEN}OK${NC} -> max_P(safe) = $VALUE"
        echo "max_safe_water,$c,$w,$WEATHER_NAME,$x,$budget,SUCCESS,$VALUE,${EXP_NAME}_results.txt" \
            >> "$PARETO_SUMMARY"
        SUCCESS_B=$((SUCCESS_B + 1))
    else
        echo -e "${RED}FAILED${NC}"
        tail -3 "$LOG_FILE" | sed 's/^/    /'
        echo "max_safe_water,$c,$w,$WEATHER_NAME,$x,$budget,FAILED,N/A,${EXP_NAME}_results.txt" \
            >> "$PARETO_SUMMARY"
        FAILED_B=$((FAILED_B + 1))
    fi

    rm -f "$TEMP_MODEL"

done; done; done; done

# ================================================================
# FINAL REPORT
# ================================================================
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
END_SECONDS=$(date +%s)
DURATION=$((END_SECONDS - START_SECONDS))

REPORT_FILE="$PROJECT_DIR/$RESULTS_DIR/multi_obj_report.txt"
{
    echo "=========================================="
    echo "Storm Multi-Objective Pareto Report — V3"
    echo "=========================================="
    echo ""
    echo "Start:    $START_TIME"
    echo "End:      $END_TIME"
    echo "Duration: $((DURATION/60))m $((DURATION%60))s"
    echo ""
    echo "Model:   $MODEL_FILE"
    echo "Engine:  $STORM_ENGINE + --prismcompat"
    echo ""
    echo "Sweep A (min water | safety >= thresh):"
    echo "  Success: $SUCCESS_A  |  Failed: $FAILED_A  |  Total: $TOTAL_A"
    echo ""
    echo "Sweep B (max safety | water <= budget):"
    echo "  Success: $SUCCESS_B  |  Failed: $FAILED_B  |  Total: $TOTAL_B"
    echo ""
    echo "Grand total: $((SUCCESS_A + SUCCESS_B)) / $TOTAL succeeded"
    echo ""
    echo "Changes from V1:"
    echo "  [C1-C4] Same calibrated uncertainty/weather as M1/M2 V3"
    echo "  [C7] Terminal self-loops (0 deadlock states)"
    echo "  w_init replaces scenario parameter"
    echo ""
    echo "Key output files:"
    echo "  $RESULTS_DIR/pareto_summary.csv"
    echo "  $RESULTS_DIR/*_results.txt"
    echo "  $LOG_DIR/*_log.txt"
    echo "=========================================="
} > "$REPORT_FILE"

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  MULTI-OBJECTIVE PARETO SWEEP COMPLETE   ${NC}"
echo -e "${GREEN}==========================================${NC}"
echo "Duration:  $((DURATION/60))m $((DURATION%60))s"
echo "Sweep A:   $SUCCESS_A / $TOTAL_A succeeded"
echo "Sweep B:   $SUCCESS_B / $TOTAL_B succeeded"
if [[ $((FAILED_A + FAILED_B)) -gt 0 ]]; then
    echo -e "Failed:    ${RED}$((FAILED_A + FAILED_B))${NC}"
fi
echo "Results:   $PROJECT_DIR/$RESULTS_DIR/"
echo "Summary:   $PARETO_SUMMARY"
echo ""
echo "Done!"