#!/bin/bash

#############################################
# MDP_Multiobj_SweepB_max_water_safe
#
# Maximise safety probability subject to water budget
#
# Property (BUDGET varies):
#   multi(Pmax=? [ G<=140 "safe" ],
#         R{"water_usage"}<=BUDGET [ C<=140 ])
#
# Parameter space:
#   c:      0.01, 0.025, 0.05
#   w_init: 0 (Dry), 1 (Moderate), 2 (Wet)
#   xinit:  20, 30, 40, 50
#   BUDGET: 15, 20, 25, 30, 40
#
#   Total: 3 x 3 x 4 x 5 = 180 runs (all c)
#          3 x 4 x 5      =  60 runs (single c)
#
# Usage:
#   bash MDP_Multiobj_SweepB_max_water_safe.sh          # all c (180 runs)
#   bash MDP_Multiobj_SweepB_max_water_safe.sh 0.01     # c=0.01  only (60 runs)
#   bash MDP_Multiobj_SweepB_max_water_safe.sh 0.025    # c=0.025 only (60 runs)
#   bash MDP_Multiobj_SweepB_max_water_safe.sh 0.05     # c=0.05  only (60 runs)
#############################################

set -u

# ---------------- CONFIGURATION ----------------
STORM_BIN="/path/to/storm/build/bin/storm"
MODEL_FILE="../models/M3/M3_mdp_synthesis.pm"
RESULTS_DIR="Results_SweepB_max_water_safe"
LOG_DIR="Logs_SweepB_max_water_safe"
STORM_ENGINE="sparse"
SWEEP_LABEL="SweepB_max_water_safe"
VALUE_LABEL="max_prob_safe"

# ---------------- STORM WRAPPER ----------------
run_storm() { "$STORM_BIN" "$@"; }

# ---------------- COLOURS ----------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; NC='\033[0m'

# ---------------- PATH SETUP ----------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"
mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  SweepB: max P(safe) | water <= BUDGET        ${NC}"
echo -e "${GREEN}  BUDGET in {15, 20, 25, 30, 40}               ${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ---------------- SANITY CHECKS ----------------
if [[ ! -f "$PROJECT_DIR/$MODEL_FILE" ]]; then
    echo -e "${RED}[ERROR] Missing model: $PROJECT_DIR/$MODEL_FILE${NC}"; exit 1
fi
if [[ ! -x "$STORM_BIN" ]]; then
    echo -e "${RED}[ERROR] Storm binary not found: $STORM_BIN${NC}"; exit 1
fi

echo "Testing Storm..."
STORM_VERSION_OUTPUT=$(run_storm --version 2>&1 | head -n 1 || true)
if echo "$STORM_VERSION_OUTPUT" | grep -qi "^storm"; then
    echo -e "${GREEN}[OK]${NC} Storm found: $STORM_VERSION_OUTPUT"
else
    echo -e "${RED}[ERROR]${NC} Storm test failed"; exit 1
fi
echo ""

# ---------------- PARAMETERS ----------------
ALL_C_VALUES=(0.01 0.025 0.05)
W_INIT_VALUES=(0 1 2)
XINIT_VALUES=(20 30 40 50)
WATER_BUDGETS=(15 20 25 30 40)   # varies in property: R{water_usage}<=BUDGET

if [[ $# -ge 1 ]]; then
    C_VALUES=("$1")
    echo -e "${YELLOW}[INFO] Running for c=$1 only${NC}"
else
    C_VALUES=("${ALL_C_VALUES[@]}")
    echo -e "${YELLOW}[INFO] Running for all c values${NC}"
fi

TOTAL=0
for c in "${C_VALUES[@]}"; do for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do for b in "${WATER_BUDGETS[@]}"; do
    TOTAL=$((TOTAL+1))
done; done; done; done

echo -e "${BLUE}Parameter Space:${NC}"
echo "  c values:      ${C_VALUES[*]}"
echo "  w_init values: ${W_INIT_VALUES[*]} (0=Dry, 1=Moderate, 2=Wet)"
echo "  xinit values:  ${XINIT_VALUES[*]} mm"
echo "  water budgets: ${WATER_BUDGETS[*]}"
echo "  Total runs:    $TOTAL"
echo "  Engine:        $STORM_ENGINE + --prismcompat"
echo ""
echo "Press Enter to start, or Ctrl+C to cancel..."
read -r

# ---------------- SUMMARY FILE ----------------
SUMMARY_FILE="$PROJECT_DIR/$RESULTS_DIR/${SWEEP_LABEL}_summary.csv"
if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "sweep,c,w_init,weather_name,xinit,water_budget,$VALUE_LABEL,status,result_file" \
        > "$SUMMARY_FILE"
fi

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_SECONDS=$(date +%s)
CURRENT=0; SUCCESS=0; FAILED=0

# ================================================================
# MAIN LOOP
# ================================================================
for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do
for budget in "${WATER_BUDGETS[@]}"; do

    CURRENT=$((CURRENT+1))
    case "$w" in
        0) WEATHER_NAME="Dry"      ;;
        1) WEATHER_NAME="Moderate" ;;
        2) WEATHER_NAME="Wet"      ;;
        *) WEATHER_NAME="Unknown"  ;;
    esac

    PROP="multi(Pmax=? [ G<=140 \"safe\" ], R{\"water_usage\"}<=${budget} [ C<=140 ])"

    EXP_NAME="${SWEEP_LABEL}_c${c}_w${w}_x${x}_b${budget}"
    RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${EXP_NAME}_results.txt"
    LOG_FILE="$PROJECT_DIR/$LOG_DIR/${EXP_NAME}_log.txt"
    TEMP_MODEL="$PROJECT_DIR/${EXP_NAME}_temp.pm"

    sed "s/x : \[0\.\.100\] init 40/x : [0..100] init $x/" \
        "$PROJECT_DIR/$MODEL_FILE" > "$TEMP_MODEL"

    echo -n "  [$CURRENT/$TOTAL] c=$c  w=$w ($WEATHER_NAME)  xinit=$x  budget=$budget ... "

    if run_storm \
        --prism "$TEMP_MODEL" \
        --prop  "$PROP" \
        --constants "c=$c,w_init=$w" \
        --engine "$STORM_ENGINE" \
        --prismcompat \
        > "$RESULT_FILE" 2> "$LOG_FILE"; then

        VALUE=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' \
                    "$RESULT_FILE" | head -1 || echo "N/A")
        echo -e "${GREEN}OK${NC}  ->  $VALUE_LABEL = $VALUE"
        echo "$SWEEP_LABEL,$c,$w,$WEATHER_NAME,$x,$budget,$VALUE,SUCCESS,${EXP_NAME}_results.txt" \
            >> "$SUMMARY_FILE"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}FAILED${NC}"
        tail -3 "$LOG_FILE" | sed 's/^/    /'
        echo "$SWEEP_LABEL,$c,$w,$WEATHER_NAME,$x,$budget,N/A,FAILED,${EXP_NAME}_results.txt" \
            >> "$SUMMARY_FILE"
        FAILED=$((FAILED+1))
    fi

    rm -f "$TEMP_MODEL"

done; done; done; done

# ================================================================
# FINAL REPORT
# ================================================================
END_SECONDS=$(date +%s)
DURATION=$((END_SECONDS - START_SECONDS))

{
    echo "================================================"
    echo "Report: $SWEEP_LABEL"
    echo "================================================"
    echo "Property: multi(Pmax=? [G<=140 safe], R{water_usage}<=BUDGET [C<=140])"
    echo "Water budgets: ${WATER_BUDGETS[*]}"
    echo "Start:    $START_TIME"
    echo "End:      $(date +"%Y-%m-%d %H:%M:%S")"
    echo "Duration: $((DURATION/60))m $((DURATION%60))s"
    echo "Model:    $MODEL_FILE"
    echo "Engine:   $STORM_ENGINE + --prismcompat"
    echo "c values: ${C_VALUES[*]}"
    echo "Results:  $SUCCESS / $TOTAL succeeded"
    [[ $FAILED -gt 0 ]] && echo "Failed:   $FAILED"
    echo "Summary:  $RESULTS_DIR/${SWEEP_LABEL}_summary.csv"
    echo "================================================"
} > "$PROJECT_DIR/$RESULTS_DIR/${SWEEP_LABEL}_report.txt"

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  $SWEEP_LABEL COMPLETE${NC}"
echo -e "${GREEN}================================================${NC}"
echo "Duration: $((DURATION/60))m $((DURATION%60))s"
echo "Success:  $SUCCESS / $TOTAL"
[[ $FAILED -gt 0 ]] && echo -e "Failed:   ${RED}$FAILED${NC}"
echo "Results:  $PROJECT_DIR/$RESULTS_DIR/"
echo "Summary:  $SUMMARY_FILE"
echo ""
echo "Done!"
