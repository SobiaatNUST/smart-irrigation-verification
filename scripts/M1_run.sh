#!/bin/bash

#############################################
# M1 Open-Loop Controller V3
# Storm Model Checking Experiment Script
#############################################
# Runs all combinations of:
#   a:      0.05, 0.06, 0.07, 0.08, 0.09
#   b:      6.0, 6.2, 6.4, 6.6, 6.8
#   c:      0.01, 0.025, 0.05
#   w_init: 0 (Dry), 1 (Moderate), 2 (Wet)
#   xinit:  20, 30, 40, 50
#
# Total: 5 x 5 x 3 x 3 x 4 = 900 experiments
#
# The open-loop controller uses:
#   u = max(0, min(umax, floor(b - a*x)))
# computed once at t=0, held for all 28 steps.
# Parameters a and b are substituted via sed.
#############################################

set -e
set -u

# ---------------- CONFIGURATION ----------------
# UPDATE THIS PATH to match your Storm installation
STORM_BIN="/path/to/storm/build/bin/storm"

MODEL_FILE="../models/M1/M1_openloop.pm"
PROPERTY_FILE="../properties/single_objective/M1_properties.props"
RESULTS_DIR="OpenLoop_V3_Results"
LOG_DIR="logs_OpenLoop_V3"

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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  M1 Open-Loop Controller V3            ${NC}"
echo -e "${GREEN}  Storm Model Checker                   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ---------------- SANITY CHECKS ----------------
for f in "$PROJECT_DIR/$MODEL_FILE" "$PROJECT_DIR/$PROPERTY_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}[ERROR] Missing: $f${NC}"
        exit 1
    fi
done

if [[ ! -x "$STORM_BIN" ]]; then
    echo -e "${RED}[ERROR] Storm binary not found or not executable at: $STORM_BIN${NC}"
    echo -e "${YELLOW}[HINT]  Update STORM_BIN in this script.${NC}"
    exit 1
fi

echo "Testing Storm..."
if run_storm --version > /dev/null 2>&1; then
    STORM_VERSION=$(run_storm --version 2>&1 | head -n 1)
    echo -e "${GREEN}[OK]${NC} Storm found: $STORM_VERSION"
else
    echo -e "${RED}[ERROR]${NC} Storm test failed"
    exit 1
fi
echo ""

# ---------------- PARAMETERS ----------------
A_VALUES=(0.05 0.06 0.07 0.08 0.09)
B_VALUES=(6.0 6.2 6.4 6.6 6.8)
C_VALUES=(0.01 0.025 0.05)
W_INIT_VALUES=(0 1 2)
XINIT_VALUES=(20 30 40 50)

# Count total experiments
TOTAL=0
for a in "${A_VALUES[@]}"; do
for b in "${B_VALUES[@]}"; do
for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do
    TOTAL=$((TOTAL + 1))
done; done; done; done; done

echo -e "${BLUE}Parameter Space:${NC}"
echo "  a values:         ${A_VALUES[*]}  (moisture sensitivity)"
echo "  b values:         ${B_VALUES[*]}  (base threshold)"
echo "  c values:         ${C_VALUES[*]}  (decay factor)"
echo "  w_init values:    ${W_INIT_VALUES[*]}  (0=Dry, 1=Moderate, 2=Wet)"
echo "  Initial moisture: ${XINIT_VALUES[*]} mm"
echo ""
echo "  a: ${#A_VALUES[@]}, b: ${#B_VALUES[@]}, c: ${#C_VALUES[@]}, w: ${#W_INIT_VALUES[@]}, x: ${#XINIT_VALUES[@]}"
echo "  TOTAL = ${#A_VALUES[@]} x ${#B_VALUES[@]} x ${#C_VALUES[@]} x ${#W_INIT_VALUES[@]} x ${#XINIT_VALUES[@]} = $TOTAL"
echo ""
echo "  Storm engine: $STORM_ENGINE"
echo ""
echo "Results: $PROJECT_DIR/$RESULTS_DIR/"
echo "Logs:    $PROJECT_DIR/$LOG_DIR/"
echo ""
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Press Enter to start experiments, or Ctrl+C to cancel..."
read -r

# ---------------- SUMMARY FILE ----------------
SUMMARY_FILE="$PROJECT_DIR/$RESULTS_DIR/experiment_summary.csv"
echo "a,b,c,w_init,weather_name,xinit,status,result_file" > "$SUMMARY_FILE"

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_SECONDS=$(date +%s)
CURRENT=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# ---------------- PROGRESS BAR ----------------
show_progress_bar() {
    local current=$1 total=$2
    local percent=$((current * 100 / total))
    local bar_width=40
    local filled=$((percent * bar_width / 100))
    local empty=$((bar_width - filled))
    printf "\r  Progress: ["
    printf "#%.0s" $(seq 1 $filled)
    printf -- "-%.0s" $(seq 1 $empty)
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
}

# ================================================================
# MAIN EXPERIMENT LOOP
# ================================================================
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Running Open-Loop V3 Experiments${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

for a in "${A_VALUES[@]}"; do
for b in "${B_VALUES[@]}"; do
for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do

    CURRENT=$((CURRENT + 1))

    case "$w" in
        0) WEATHER_NAME="Dry"      ;;
        1) WEATHER_NAME="Moderate" ;;
        2) WEATHER_NAME="Wet"      ;;
    esac

    EXP_NAME="a${a}_b${b}_c${c}_w${w}_x${x}"

    # Show progress every 10 experiments to avoid excessive output
    if (( CURRENT % 10 == 1 )) || (( CURRENT == TOTAL )); then
        show_progress_bar "$CURRENT" "$TOTAL"
        echo ""
        echo -e "  ${BLUE}[$CURRENT/$TOTAL]${NC} a=$a, b=$b, c=$c, w_init=$w ($WEATHER_NAME), xinit=$x"
    fi

    RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${EXP_NAME}_results.txt"
    LOG_FILE="$PROJECT_DIR/$LOG_DIR/${EXP_NAME}_log.txt"
    TEMP_MODEL="$PROJECT_DIR/${EXP_NAME}_temp.pm"

    # Create temporary model with substituted a, b, and xinit values
    sed -e "s/const double a = 0.07;/const double a = $a;/" \
        -e "s/const double b = 6.4;/const double b = $b;/" \
        -e "s/x : \[0\.\.100\] init 40/x : [0..100] init $x/" \
        "$PROJECT_DIR/$MODEL_FILE" > "$TEMP_MODEL"

    # Write header to result file
    {
        echo "========================================"
        echo "Storm Model Checking Results"
        echo "M1 Open-Loop Controller V3"
        echo "========================================"
        echo "Date:      $(date)"
        echo "a=$a, b=$b, c=$c, w_init=$w ($WEATHER_NAME), xinit=$x"
        echo "Model:     $MODEL_FILE"
        echo "Engine:    $STORM_ENGINE"
        echo "========================================"
        echo ""
        echo "Control formula: u = max(0, min(10, floor($b - $a * x)))"
        echo ""
    } > "$RESULT_FILE"

    # Run Storm
    if run_storm \
        --prism "$TEMP_MODEL" \
        --prop  "$PROJECT_DIR/$PROPERTY_FILE" \
        --constants "c=$c,w_init=$w" \
        --engine "$STORM_ENGINE" \
        >> "$RESULT_FILE" 2> "$LOG_FILE"; then

        echo "$a,$b,$c,$w,$WEATHER_NAME,$x,SUCCESS,${EXP_NAME}_results.txt" >> "$SUMMARY_FILE"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo -e "  ${RED}[FAILED]${NC} a=$a b=$b c=$c w=$w x=$x -> $LOG_DIR/${EXP_NAME}_log.txt"
        echo "$a,$b,$c,$w,$WEATHER_NAME,$x,FAILED,${EXP_NAME}_results.txt" >> "$SUMMARY_FILE"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    # Clean up temporary model
    rm -f "$TEMP_MODEL"

done
done
done
done
done

# ================================================================
# FINAL REPORT
# ================================================================
END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
END_SECONDS=$(date +%s)
DURATION=$((END_SECONDS - START_SECONDS))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

REPORT_FILE="$PROJECT_DIR/$RESULTS_DIR/comprehensive_report.txt"
{
    echo "========================================"
    echo "M1 Open-Loop Controller V3"
    echo "Storm Comprehensive Report"
    echo "========================================"
    echo ""
    echo "Start:    $START_TIME"
    echo "End:      $END_TIME"
    echo "Duration: ${DURATION_MIN}m ${DURATION_SEC}s"
    echo ""
    echo "Total Experiments: $TOTAL"
    echo "Successful: $SUCCESS_COUNT"
    echo "Failed: $FAILED_COUNT"
    echo ""
    echo "Model:      $MODEL_FILE"
    echo "Properties: $PROPERTY_FILE"
    echo "Engine:     $STORM_ENGINE"
    echo ""
    echo "Parameter Space:"
    echo "  a values: ${A_VALUES[*]}  (moisture sensitivity)"
    echo "  b values: ${B_VALUES[*]}  (base threshold)"
    echo "  c values: ${C_VALUES[*]}  (decay factor)"
    echo "  w_init:   ${W_INIT_VALUES[*]}  (0=Dry, 1=Moderate, 2=Wet)"
    echo "  xinit:    ${XINIT_VALUES[*]} mm"
    echo ""
    echo "Control formula: u = max(0, min(10, floor(b - a*x)))"
    echo "Irrigation computed once at t=0, held for all 28 steps."
    echo ""
    echo "Changes from V1:"
    echo "  [C1] ET uncertainty: 5-point eta in [-2,+2], E[eta]=+0.27mm"
    echo "  [C2] Precip uncertainty: 3-regime forecast-proportional bounds"
    echo "  [C3] ET forecast range: e_hat in [1,4] (was [2,3])"
    echo "  [C4] Markov weather: 3-state chain replaces i.i.d. scenarios"
    echo "  [C7] Terminal self-loops in all modules"
    echo ""
    echo "Output Files:"
    echo "  Results:   $RESULTS_DIR/"
    echo "  Logs:      $LOG_DIR/"
    echo "  Summary:   $RESULTS_DIR/experiment_summary.csv"
    echo "  Report:    $RESULTS_DIR/comprehensive_report.txt"
    echo "========================================"
} > "$REPORT_FILE"

# Display final summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ALL EXPERIMENTS COMPLETE               ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Total Experiments: $TOTAL"
echo -e "Successful: ${GREEN}$SUCCESS_COUNT${NC}"
if [[ $FAILED_COUNT -gt 0 ]]; then
    echo -e "Failed: ${RED}$FAILED_COUNT${NC}"
else
    echo -e "Failed: ${GREEN}$FAILED_COUNT${NC}"
fi
echo ""
echo "Duration: ${DURATION_MIN}m ${DURATION_SEC}s"
echo ""
echo "Results: $PROJECT_DIR/$RESULTS_DIR/"
echo "Summary: $SUMMARY_FILE"
echo "Report:  $REPORT_FILE"
echo ""

# Display first few rows of summary
if [[ -f "$SUMMARY_FILE" ]]; then
    echo "Sample results (first 10):"
    head -11 "$SUMMARY_FILE" | column -t -s ','
    echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo "Done!"
