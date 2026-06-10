#!/bin/bash
###############################################################################
# run_tier1_named_policies.sh
#
# TIER 1: Named policies for all 9 (c, w_init) scenarios at xinit=40
#         3 queries x 9 scenarios = 27 runs
#
# Queries:
#   P1: min water subject to P(safe) >= 0.90
#   P2: min water subject to P(safe) >= 0.95
#   P3: max P(safe) subject to water <= 40 mm
#
# Purpose: Concrete, citable numbers for M3 rows in Tables 3-4.
#          Replaces the broken min/max average with actual named policies.
#
# Output:  CSV at Results_T1_Named_Policies/t1_named_policies.csv
#
# Checkpoint system:
#   - Each completed scenario writes a .done file in Checkpoints_T1/
#   - On restart, already-completed scenarios are skipped automatically
#   - The CSV is rebuilt from checkpoint files on resume so it stays consistent
#   - To force a full re-run from scratch: pass --fresh
#
# Usage:
#   chmod +x run_tier1_named_policies.sh
#   ./run_tier1_named_policies.sh                       # sequential
#   ./run_tier1_named_policies.sh --parallel 4           # 4 concurrent jobs
#   ./run_tier1_named_policies.sh --storm /path/to/storm # custom Storm path
#   ./run_tier1_named_policies.sh --fresh                # wipe checkpoints, start over
#
# Estimated time: 27 runs x ~66 min = ~30 h sequential, ~8 h @ 4 cores
###############################################################################

set -euo pipefail

# ======================== CONFIGURATION ======================================

STORM_BIN="/path/to/storm/build/bin/storm"    # <-- EDIT THIS
MODEL_FILE="../models/M3/M3_mdp_synthesis.pm"
STORM_ENGINE="sparse"

RESULTS_DIR="Results_T1_Named_Policies"
LOG_DIR="Logs_T1_Named_Policies"
CHECKPOINT_DIR="Checkpoints_T1"
CSV_FILE="t1_named_policies.csv"

MAX_JOBS=1
XINIT=40
FRESH=0

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
        --fresh)    FRESH=1; shift ;;
        --help|-h)
            echo "Usage: $0 [--parallel N] [--storm PATH] [--model FILE] [--xinit N] [--fresh]"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ======================== PATH SETUP =========================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"
mkdir -p "$PROJECT_DIR/$CHECKPOINT_DIR"

CSV_PATH="$PROJECT_DIR/$CSV_FILE"

# ======================== FRESH START ========================================

if (( FRESH )); then
    echo -e "${YELLOW}[--fresh] Wiping all checkpoints and results...${NC}"
    rm -f "$PROJECT_DIR/$CHECKPOINT_DIR"/*.done
    rm -f "$CSV_PATH"
    echo -e "${YELLOW}[--fresh] Done. Starting from scratch.${NC}"
    echo ""
fi

# ======================== SANITY CHECKS ======================================

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  TIER 1: Named Policies  (27 runs)                         ${NC}"
echo -e "${GREEN}  9 scenarios x 3 queries, xinit=${XINIT}                   ${NC}"
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

# ======================== CHECKPOINT HELPERS =================================

checkpoint_file() {
    # Returns the path of the .done file for a scenario
    echo "$PROJECT_DIR/$CHECKPOINT_DIR/${1}.done"
}

is_done() {
    # Returns 0 (true) if scenario already has a valid checkpoint
    local cp
    cp=$(checkpoint_file "$1")
    [[ -f "$cp" ]] && grep -q "^STATUS=OK$" "$cp"
}

mark_done() {
    # Writes a checkpoint file for a completed scenario
    local scenario="$1"; shift
    local cp
    cp=$(checkpoint_file "$scenario")
    # Write all CSV fields into the checkpoint so we can rebuild the CSV later
    printf '%s\n' "$@" > "$cp"
    echo "STATUS=OK" >> "$cp"
}

# ======================== CSV INITIALISATION =================================
# Always write a fresh header, then replay all existing checkpoints into it.
# This way the CSV is always consistent with checkpoint state.

CSV_HEADER="tier,scenario,c,w_init,w_name,xinit,query_id,query_desc,property,result,states,transitions,build_sec,check_sec,wall_sec"
echo "$CSV_HEADER" > "$CSV_PATH"

RESUMED=0
shopt -s nullglob
for cp in "$PROJECT_DIR/$CHECKPOINT_DIR"/*.done; do
    grep -q "^STATUS=OK$" "$cp" || continue
    # The CSV row is everything except the last STATUS=OK line
    grep -v "^STATUS=" "$cp" >> "$CSV_PATH"
    (( RESUMED++ )) || true
done
shopt -u nullglob

if (( RESUMED > 0 )); then
    echo -e "${CYAN}[RESUME] Loaded ${RESUMED} completed scenario(s) from checkpoints — skipping those.${NC}"
else
    echo -e "${BLUE}[START]  No prior checkpoints found — running all 27 scenarios.${NC}"
fi
echo ""

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

    # ---- CHECKPOINT CHECK ---------------------------------------------------
    if is_done "$scenario"; then
        echo -e "${BLUE}[SKIP]${NC} ${scenario}  (already completed)"
        return
    fi
    # -------------------------------------------------------------------------

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

        value=$(perl -ne 'print $1 if /Result \(for initial states\): ([0-9.eE+\-]+)/' \
                    "$result_file" | head -1 || echo "N/A")
        states=$(perl -ne 'print $1 if /States:\s+([0-9]+)/' \
                    "$result_file" | head -1 || echo "N/A")
        transitions=$(perl -ne 'print $1 if /Transitions:\s+([0-9]+)/' \
                    "$result_file" | head -1 || echo "N/A")
        build_sec=$(perl -ne 'print $1 if /Time for model construction:\s+([0-9.]+)/' \
                    "$result_file" | head -1 || echo "N/A")
        check_sec=$(perl -ne 'print $1 if /Time for model checking:\s+([0-9.]+)/' \
                    "$result_file" | head -1 || echo "N/A")

        local csv_row="${tier},${scenario},${c},${w_init},${w_name},${xinit},${qid},\"${qdesc}\",\"${prop}\",${value},${states},${transitions},${build_sec},${check_sec},${wall}"

        # Write to CSV and save checkpoint atomically
        echo "$csv_row" >> "$CSV_PATH"
        mark_done "$scenario" "$csv_row"

        echo -e "${GREEN}[OK]${NC}  ${scenario}  result=${value}  wall=${wall}s ($(( wall / 60 ))m$(( wall % 60 ))s)"
    else
        local end_ts wall
        end_ts=$(date +%s)
        wall=$(( end_ts - start_ts ))

        # FAILED runs are NOT checkpointed — they will be retried on next run
        echo "${tier},${scenario},${c},${w_init},${w_name},${xinit},${qid},\"${qdesc}\",\"${prop}\",FAILED,N/A,N/A,N/A,N/A,${wall}" \
            >> "$CSV_PATH"

        echo -e "${RED}[FAIL]${NC} ${scenario}  wall=${wall}s  (will retry on next run)"
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

# ======================== RUN ALL 27 JOBS ====================================

RUN_COUNT=0

for i in "${!SOILS[@]}"; do
    c="${SOILS[$i]}"
    c_name="${SOIL_NAMES[$i]}"

    for j in "${!WEATHERS[@]}"; do
        w="${WEATHERS[$j]}"
        w_name="${WEATHER_NAMES[$j]}"

        echo -e "${YELLOW}--- ${c_name}, ${w_name} start, xinit=${XINIT} ---${NC}"

        # P1: min water for 90% safety
        run_storm_bg "T1" "$c" "$w" "$w_name" "$XINIT" \
            "P1_safe90" "min_water_Psafe_ge_0.90" \
            "multi(R{\"water_usage\"}min=? [C<=140], P>=0.90 [G \"safe\"])"
        (( RUN_COUNT++ ))

        # P2: min water for 95% safety
        run_storm_bg "T1" "$c" "$w" "$w_name" "$XINIT" \
            "P2_safe95" "min_water_Psafe_ge_0.95" \
            "multi(R{\"water_usage\"}min=? [C<=140], P>=0.95 [G \"safe\"])"
        (( RUN_COUNT++ ))

        # P3: max safety for water <= 40mm
        run_storm_bg "T1" "$c" "$w" "$w_name" "$XINIT" \
            "P3_maxsafe_w40" "max_Psafe_water_le_40" \
            "multi(Pmax=? [G \"safe\"], R{\"water_usage\"}<=40 [C<=140])"
        (( RUN_COUNT++ ))
    done
done

wait

# ======================== SUMMARY ============================================

TOTAL_ROWS=$(tail -n +2 "$CSV_PATH" | wc -l)
FAILED_ROWS=$(grep -c ",FAILED," "$CSV_PATH" || true)
OK_ROWS=$(( TOTAL_ROWS - FAILED_ROWS ))
DONE_FILES=$(find "$PROJECT_DIR/$CHECKPOINT_DIR" -name "*.done" 2>/dev/null | wc -l || echo 0)

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  TIER 1 COMPLETE                                            ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  CSV:            ${CYAN}${CSV_PATH}${NC}"
echo -e "  Checkpoints:    ${CYAN}${PROJECT_DIR}/${CHECKPOINT_DIR}/${NC}"
echo -e "  Runs in CSV:    ${TOTAL_ROWS} / ${RUN_COUNT} expected"
echo -e "  Succeeded:      ${GREEN}${OK_ROWS}${NC}"
echo -e "  Failed:         ${RED}${FAILED_ROWS}${NC}  (will auto-retry on next run)"
echo -e "  Done files:     ${DONE_FILES}"
echo ""
if (( FAILED_ROWS > 0 )); then
    echo -e "  ${YELLOW}Re-run the script to retry failed scenarios.${NC}"
    echo -e "  ${YELLOW}Use --fresh to wipe all checkpoints and start over.${NC}"
fi
echo ""
echo "  Queries per scenario:"
echo "    P1: min water s.t. P(safe) >= 0.90  --> paper Table: sigma*(P>=0.90)"
echo "    P2: min water s.t. P(safe) >= 0.95  --> paper Table: sigma*(P>=0.95)"
echo "    P3: max P(safe) s.t. water <= 40mm  --> paper Table: sigma*(budget<=40)"
echo ""
echo "Next: pivot CSV in pandas -->  rows=(c, w_init), cols=(P1, P2, P3)"
echo ""