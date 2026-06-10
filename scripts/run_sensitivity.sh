#!/bin/bash
###############################################################################
# run_tier3_sensitivity.sh
#
# TIER 3: Sensitivity check at xinit=30 for all 9 (c, w_init) scenarios
#         1 query x 9 scenarios = 9 runs
#
# Repeats the key Tier 1 query (P2: min water for 95% safety) at xinit=30
# instead of xinit=40. This tests whether starting at the safety threshold
# x_min = 30 mm changes the conclusions qualitatively.
#
# Compare results with Tier 1 P2 values (xinit=40) to quantify
# initial-condition sensitivity over the 7-day horizon.
#
# Output:  CSV at Results_T3_Sensitivity/t3_sensitivity.csv
#
# Usage:
#   chmod +x run_tier3_sensitivity.sh
#   ./run_tier3_sensitivity.sh                       # sequential
#   ./run_tier3_sensitivity.sh --parallel 4           # 4 concurrent jobs
#   ./run_tier3_sensitivity.sh --storm /path/to/storm # custom Storm path
#   ./run_tier3_sensitivity.sh --xinit 20             # test at xinit=20
#
# Estimated time: 9 runs x ~66 min = ~10 h sequential, ~3 h @ 4 cores
###############################################################################

set -euo pipefail

# ======================== CONFIGURATION ======================================

STORM_BIN="/path/to/storm/build/bin/storm"    # <-- EDIT THIS
MODEL_FILE="../models/M3/M3_mdp_synthesis.pm"
STORM_ENGINE="sparse"

RESULTS_DIR="Results_T3_Sensitivity"
LOG_DIR="Logs_T3_Sensitivity"
CSV_FILE="t3_sensitivity.csv"

MAX_JOBS=1
XINIT=30

# ======================== COLOURS ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ======================== CLI ARGS ===========================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel) MAX_JOBS="$2"; shift 2 ;;
        --storm)    STORM_BIN="$2"; shift 2 ;;
        --model)    MODEL_FILE="$2"; shift 2 ;;
        --xinit)    XINIT="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--parallel N] [--storm PATH] [--model FILE] [--xinit N]"
            echo ""
            echo "Default xinit=30 (at safety threshold). Use --xinit 20 for"
            echo "severely stressed start."
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ======================== PATH SETUP =========================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"

CSV_PATH="$PROJECT_DIR/$CSV_FILE"

# ======================== SANITY CHECKS ======================================

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  TIER 3: Sensitivity Check  (9 runs)                       ${NC}"
echo -e "${GREEN}  xinit=${XINIT}mm  (compare with Tier 1 at xinit=40)       ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

if [[ ! -f "$PROJECT_DIR/$MODEL_FILE" ]]; then
    echo -e "${RED}[ERROR] Model not found: $PROJECT_DIR/$MODEL_FILE${NC}"
    exit 1
fi

if [[ ! -x "$STORM_BIN" ]]; then
    echo -e "${RED}[ERROR] Storm binary not found or not executable: $STORM_BIN${NC}"
    echo "  Use:  $0 --storm /path/to/storm/build/bin/storm"
    exit 1
fi

STORM_VER=$("$STORM_BIN" --version 2>&1 | head -1 || true)
echo -e "Storm:    ${CYAN}$STORM_VER${NC}"
echo -e "Model:    $MODEL_FILE"
echo -e "Engine:   $STORM_ENGINE"
echo -e "xinit:    $XINIT"
echo -e "Parallel: $MAX_JOBS jobs"
echo ""

# ======================== CSV HEADER =========================================

echo "tier,scenario,c,w_init,w_name,xinit,query_id,query_desc,property,result,states,transitions,build_sec,check_sec,wall_sec" \
    > "$CSV_PATH"

# ======================== PARAMETER SPACE ====================================

SOILS=(0.01 0.025 0.05)
SOIL_NAMES=("clay" "loam" "sandy_loam")
WEATHERS=(0 1 2)
WEATHER_NAMES=("Dry" "Moderate" "Wet")

# ======================== CORE RUN FUNCTION ==================================

run_storm() {
    local tier="$1" c="$2" w_init="$3" w_name="$4" xinit="$5"
    local qid="$6" qdesc="$7" prop="$8"

    local scenario="${tier}_c${c}_w${w_init}_x${xinit}_${qid}"
    local result_file="$PROJECT_DIR/$RESULTS_DIR/${scenario}.txt"
    local log_file="$PROJECT_DIR/$LOG_DIR/${scenario}.log"

    # Patch xinit in model
    local temp_model="$PROJECT_DIR/${scenario}_temp.pm"
    sed "s/x : \[0\.\.100\] init [0-9]*/x : [0..100] init $xinit/" \
        "$PROJECT_DIR/$MODEL_FILE" > "$temp_model"

    local start_ts
    start_ts=$(date +%s)

    if "$STORM_BIN" \
        --prism "$temp_model" \
        --prop "$prop" \
        --constants "c=$c,w_init=$w_init" \
        --engine "$STORM_ENGINE" \
        --prismcompat \
        --statistics \
        > "$result_file" 2> "$log_file"; then

        local end_ts wall value states transitions build_sec check_sec
        end_ts=$(date +%s)
        wall=$(( end_ts - start_ts ))

        value=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' \
                    "$result_file" | head -1 || echo "N/A")
        states=$(grep -oP 'States:\s+\K[0-9]+' "$result_file" | head -1 || echo "N/A")
        transitions=$(grep -oP 'Transitions:\s+\K[0-9]+' "$result_file" | head -1 || echo "N/A")
        build_sec=$(grep -oP 'Time for model construction:\s+\K[0-9.]+' "$result_file" | head -1 || echo "N/A")
        check_sec=$(grep -oP 'Time for model checking:\s+\K[0-9.]+' "$result_file" | head -1 || echo "N/A")

        echo "${tier},${scenario},${c},${w_init},${w_name},${xinit},${qid},\"${qdesc}\",\"${prop}\",${value},${states},${transitions},${build_sec},${check_sec},${wall}" \
            >> "$CSV_PATH"

        echo -e "${GREEN}[OK]${NC}  ${scenario}  result=${value}  wall=${wall}s ($(( wall / 60 ))m$(( wall % 60 ))s)"
    else
        local end_ts wall
        end_ts=$(date +%s)
        wall=$(( end_ts - start_ts ))

        echo "${tier},${scenario},${c},${w_init},${w_name},${xinit},${qid},\"${qdesc}\",\"${prop}\",FAILED,N/A,N/A,N/A,N/A,${wall}" \
            >> "$CSV_PATH"

        echo -e "${RED}[FAIL]${NC} ${scenario}  wall=${wall}s"
        echo "  Log: $log_file"
        tail -3 "$log_file" 2>/dev/null | sed 's/^/  /'
    fi

    rm -f "$temp_model"
}

run_storm_bg() {
    if (( MAX_JOBS > 1 )); then
        while (( $(jobs -rp | wc -l) >= MAX_JOBS )); do
            sleep 2
        done
        run_storm "$@" &
    else
        run_storm "$@"
    fi
}

# ======================== RUN ALL 9 SCENARIOS ================================

PROP="multi(R{\"water_usage\"}min=? [C<=140], P>=0.95 [G<=140 \"safe\"])"

for i in "${!SOILS[@]}"; do
    c="${SOILS[$i]}"
    c_name="${SOIL_NAMES[$i]}"

    for j in "${!WEATHERS[@]}"; do
        w="${WEATHERS[$j]}"
        w_name="${WEATHER_NAMES[$j]}"

        echo -e "${YELLOW}--- ${c_name}, ${w_name} start, xinit=${XINIT} ---${NC}"

        run_storm_bg "T3" "$c" "$w" "$w_name" "$XINIT" \
            "P2_safe95_sens" "sensitivity_min_water_Psafe_ge_0.95_xinit${XINIT}" \
            "$PROP"
    done
done

wait

# ======================== SUMMARY ============================================

TOTAL_ROWS=$(tail -n +2 "$CSV_PATH" | wc -l)
FAILED_ROWS=$(grep -c "FAILED" "$CSV_PATH" || true)
OK_ROWS=$(( TOTAL_ROWS - FAILED_ROWS ))

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  TIER 3 COMPLETE                                            ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  CSV:        ${CYAN}${CSV_PATH}${NC}"
echo -e "  Runs:       ${TOTAL_ROWS} / 9 expected"
echo -e "  Succeeded:  ${GREEN}${OK_ROWS}${NC}"
echo -e "  Failed:     ${RED}${FAILED_ROWS}${NC}"
echo ""
echo "  Query: min water s.t. P(safe) >= 0.95 at xinit=${XINIT}"
echo ""
echo "  How to interpret:"
echo "    Compare each (c, w_init) row with the corresponding P2 row"
echo "    from Tier 1 (xinit=40). If the difference is small (<5 mm),"
echo "    initial conditions wash out over the 7-day horizon. If large,"
echo "    report it as a sensitivity finding."
echo ""
echo "  To test other initial conditions:"
echo "    $0 --xinit 20    # severely stressed"
echo "    $0 --xinit 50    # comfortable start"
echo ""
