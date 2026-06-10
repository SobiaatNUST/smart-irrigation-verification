#!/bin/bash

#############################################
# M2 Threshold-Based Heuristic Controller V3
# PRISM Model Checking Experiment Script
#############################################
# Runs all combinations of:
#   - c values:     0.01, 0.025, 0.05
#   - w_init values: 0 (Dry), 1 (Moderate), 2 (Wet)
#   - xinit values: 20, 30, 40, 50
#
# Total experiments: 3 x 3 x 4 = 36
#############################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# ---------------- CONFIGURATION ----------------
# UPDATE THIS PATH to match your PRISM installation
PRISM_DIR="/home/user/prism-4.8.1"

MODEL_FILE="../models/M2/M2_threshold_zones.pm"
PROPERTY_FILE="../properties/single_objective/M2_properties.pctl"
RESULTS_DIR="ThresholdBased_V3_Results"
LOG_DIR="logs_ThresholdBased_V3"

# ---------------- COLORS FOR OUTPUT ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------- PATH SETUP ----------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

# Create output directories
mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}M2 Threshold-Based Heuristic V3${NC}"
echo -e "${GREEN}PRISM Experimental Analysis${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Project Directory: $PROJECT_DIR"
echo "PRISM Directory:   $PRISM_DIR"
echo ""

# ---------------- SANITY CHECKS ----------------

if [[ ! -f "$PROJECT_DIR/$MODEL_FILE" ]]; then
    echo -e "${RED}[ERROR] Model file not found: $PROJECT_DIR/$MODEL_FILE${NC}"
    ls -la "$PROJECT_DIR"
    exit 1
fi

if [[ ! -f "$PROJECT_DIR/$PROPERTY_FILE" ]]; then
    echo -e "${RED}[ERROR] Property file not found: $PROJECT_DIR/$PROPERTY_FILE${NC}"
    ls -la "$PROJECT_DIR"
    exit 1
fi

if [[ ! -d "$PRISM_DIR" ]]; then
    echo -e "${RED}[ERROR] PRISM directory not found: $PRISM_DIR${NC}"
    echo "Please update PRISM_DIR in this script"
    exit 1
fi

if [[ ! -f "$PRISM_DIR/bin/prism" ]]; then
    echo -e "${RED}[ERROR] PRISM executable not found: $PRISM_DIR/bin/prism${NC}"
    ls -la "$PRISM_DIR/bin/" 2>/dev/null || echo "Directory not accessible"
    exit 1
fi

if [[ ! -x "$PRISM_DIR/bin/prism" ]]; then
    echo -e "${YELLOW}[WARNING] PRISM is not executable. Attempting to fix...${NC}"
    chmod +x "$PRISM_DIR/bin/prism" 2>/dev/null || {
        echo -e "${RED}[ERROR] Cannot make PRISM executable.${NC}"
        exit 1
    }
fi

echo -e "${GREEN}[OK]${NC} Model file: $MODEL_FILE"
echo -e "${GREEN}[OK]${NC} Property file: $PROPERTY_FILE"
echo -e "${GREEN}[OK]${NC} PRISM found"
echo ""

# Test PRISM
echo "Testing PRISM..."
if "$PRISM_DIR/bin/prism" -help > /dev/null 2>&1; then
    echo -e "${GREEN}[OK]${NC} PRISM test passed"
else
    echo -e "${RED}[ERROR]${NC} PRISM test failed"
    exit 1
fi
echo ""

echo -e "${BLUE}PRISM Configuration:${NC}"
echo "  Engine: EXPLICIT (forced via -explicit flag)"
echo "  Java Memory: 4GB"
echo "  CUDD Memory: 2GB"
echo "  Model: $MODEL_FILE"
echo ""

# ---------------- PARAMETERS ----------------

C_VALUES=(0.01 0.025 0.05)
W_INIT_VALUES=(0 1 2)
XINIT_VALUES=(20 30 40 50)

# Count total experiments
TOTAL=0
for c in "${C_VALUES[@]}"; do
  for w in "${W_INIT_VALUES[@]}"; do
    for x in "${XINIT_VALUES[@]}"; do
      TOTAL=$((TOTAL+1))
    done
  done
done

echo -e "${BLUE}Total Experiments: $TOTAL${NC}"
echo ""
echo "Parameter Space:"
echo "  c values:       ${C_VALUES[*]}"
echo "  w_init values:  ${W_INIT_VALUES[*]} (0=Dry, 1=Moderate, 2=Wet)"
echo "  Initial moisture: ${XINIT_VALUES[*]} mm"
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
echo "c,w_init,weather_name,xinit,status,result_file" > "$SUMMARY_FILE"

START_TIME=$(date +"%Y-%m-%d %H:%M:%S")
START_SECONDS=$(date +%s)
CURRENT=0
SUCCESS_COUNT=0
FAILED_COUNT=0

# ---------------- MAIN LOOP ----------------

for c in "${C_VALUES[@]}"; do
for w in "${W_INIT_VALUES[@]}"; do
for x in "${XINIT_VALUES[@]}"; do

  CURRENT=$((CURRENT+1))

  case "$w" in
    0) WEATHER_NAME="Dry" ;;
    1) WEATHER_NAME="Moderate" ;;
    2) WEATHER_NAME="Wet" ;;
    *) WEATHER_NAME="Unknown" ;;
  esac

  EXP_NAME="c${c}_w${w}_x${x}"

  echo -e "${BLUE}[$CURRENT/$TOTAL]${NC} Running: c=$c, w_init=$w ($WEATHER_NAME), xinit=$x"

  RESULT_FILE="$PROJECT_DIR/$RESULTS_DIR/${EXP_NAME}_results.txt"
  LOG_FILE="$PROJECT_DIR/$LOG_DIR/${EXP_NAME}_log.txt"
  TEMP_MODEL="$PROJECT_DIR/${EXP_NAME}_temp.pm"

  # Create temporary model with modified xinit
  if sed "s/x : \[0\.\.100\] init 40/x : [0..100] init $x/" "$PROJECT_DIR/$MODEL_FILE" > "$TEMP_MODEL"; then

    # Write header to result file
    {
      echo "========================================"
      echo "PRISM Model Checking Results"
      echo "M2 Threshold-Based Heuristic Controller V3"
      echo "========================================"
      echo "Experiment: c=$c, w_init=$w ($WEATHER_NAME), xinit=$x"
      echo "Model File: $MODEL_FILE"
      echo "Engine: EXPLICIT"
      echo "Date: $(date)"
      echo "========================================"
      echo ""
      echo "PARAMETERS:"
      echo "  c      = $c"
      echo "  w_init = $w ($WEATHER_NAME)"
      echo "  xinit  = $x"
      echo "  umax   = 10 (constant)"
      echo "  xmin   = 30 (safety threshold)"
      echo ""
      echo "RESULTS:"
      echo "----------------------------------------"
    } > "$RESULT_FILE"

    # Run PRISM with EXPLICIT engine
    echo "  Running PRISM with EXPLICIT engine..."

    if "$PRISM_DIR/bin/prism" "$TEMP_MODEL" "$PROJECT_DIR/$PROPERTY_FILE" \
      -const "c=$c,w_init=$w" \
      -explicit \
      -javamaxmem 4g \
      -cuddmaxmem 2g \
      >> "$RESULT_FILE" 2> "$LOG_FILE"; then

      echo -e "  ${GREEN}[SUCCESS]${NC} Complete"
      echo "$c,$w,$WEATHER_NAME,$x,SUCCESS,${EXP_NAME}_results.txt" >> "$SUMMARY_FILE"
      SUCCESS_COUNT=$((SUCCESS_COUNT+1))
    else
      echo -e "  ${RED}[FAILED]${NC} Check log: $LOG_DIR/${EXP_NAME}_log.txt"
      echo "" >> "$RESULT_FILE"
      echo "ERROR: PRISM execution failed" >> "$RESULT_FILE"
      echo "$c,$w,$WEATHER_NAME,$x,FAILED,${EXP_NAME}_results.txt" >> "$SUMMARY_FILE"
      FAILED_COUNT=$((FAILED_COUNT+1))
    fi

    # Clean up temporary file
    rm -f "$TEMP_MODEL"
  else
    echo -e "  ${RED}[ERROR]${NC} Failed to create temporary model"
    echo "$c,$w,$WEATHER_NAME,$x,FAILED,TEMP_MODEL_ERROR" >> "$SUMMARY_FILE"
    FAILED_COUNT=$((FAILED_COUNT+1))
  fi

  echo "  Saved to: $RESULTS_DIR/${EXP_NAME}_results.txt"
  echo ""

done
done
done

# ---------------- FINAL REPORT ----------------

END_TIME=$(date +"%Y-%m-%d %H:%M:%S")
END_SECONDS=$(date +%s)
DURATION=$((END_SECONDS - START_SECONDS))
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

REPORT_FILE="$PROJECT_DIR/$RESULTS_DIR/comprehensive_report.txt"

{
  echo "========================================"
  echo "M2 Threshold-Based Heuristic V3"
  echo "Comprehensive Experiment Report"
  echo "========================================"
  echo ""
  echo "Project Directory: $PROJECT_DIR"
  echo "Start Time: $START_TIME"
  echo "End Time:   $END_TIME"
  echo "Duration:   ${DURATION_MIN}m ${DURATION_SEC}s"
  echo ""
  echo "Total Experiments: $TOTAL"
  echo "Successful: $SUCCESS_COUNT"
  echo "Failed: $FAILED_COUNT"
  echo ""
  echo "Configuration:"
  echo "  Engine: EXPLICIT (forced)"
  echo "  Java Memory: 4GB"
  echo "  CUDD Memory: 2GB"
  echo "  Model: $MODEL_FILE"
  echo "  Properties: $PROPERTY_FILE"
  echo ""
  echo "Parameter Space:"
  echo "  c values:       ${C_VALUES[*]}"
  echo "  w_init values:  ${W_INIT_VALUES[*]} (0=Dry, 1=Moderate, 2=Wet)"
  echo "  Initial moisture: ${XINIT_VALUES[*]} mm"
  echo ""
  echo "Changes from V1:"
  echo "  [C1] ET uncertainty: 5-point eta in [-2,+2], E[eta]=+0.27mm"
  echo "  [C2] Precip uncertainty: 3-regime forecast-proportional bounds"
  echo "  [C3] ET forecast range: e_hat in [1,4] (was [2,3])"
  echo "  [C4] Markov weather: 3-state chain replaces i.i.d. scenarios"
  echo "  [C5] Controller renamed and updated for expanded e_hat range"
  echo "  [C7] Terminal self-loops in all modules"
  echo ""
  echo "Output Files:"
  echo "  Results:   $RESULTS_DIR/"
  echo "  Logs:      $LOG_DIR/"
  echo "  Summary:   $RESULTS_DIR/experiment_summary.csv"
  echo "  Report:    $RESULTS_DIR/comprehensive_report.txt"
  echo ""
  echo "========================================"
} > "$REPORT_FILE"

# Display final summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ALL EXPERIMENTS COMPLETE${NC}"
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
echo "Results saved in:"
echo "  $PROJECT_DIR/$RESULTS_DIR/"
echo ""
echo "Summary CSV:"
echo "  $SUMMARY_FILE"
echo ""

# Display first few rows of summary
if [[ -f "$SUMMARY_FILE" ]]; then
  echo "Sample results (first 10 experiments):"
  head -11 "$SUMMARY_FILE" | column -t -s ','
  echo ""
fi

echo -e "${GREEN}========================================${NC}"
echo "Done!"
