#!/bin/bash
###############################################################################
# run_mo4_grid.sh   (originally named run_phi_mo2.sh in development tree;
#                    renamed to match the paper's reordered MO labelling
#                    where MO4 = water under violation budget)
###############################################################################
# Paper convention (eq. 17):
#   phi_mo4 : multi( R{"water_usage"}min=?            [C<=140],
#                    R{"safety_violations"}<=V        [C<=140] )
# Sweeps V in {0.05, 0.5, 1.0} across the 3x3 soil x weather grid at x(0)=40.
###############################################################################
#
# ----- Original header below -----
#
# Storm batch runner for the second missing multi-objective query of the
# SIS paper:
#
#     phi_mo2 :  multi( R{"water_usage"}min=? [ C<=140 ],
#                       R{"safety_violations"}<= c    [ C<=140 ] )
#
# This minimises expected cumulative water under a cap on the expected
# count of safety violations. Three thresholds are swept:
#
#     c in { 0.05, 0.5, 1.0 }
#
# Factorial:
#     c_soil     in { 0.01 (clay), 0.025 (loam), 0.05 (sandy loam) }
#     w_init     in { 0 (Dry), 1 (Moderate), 2 (Wet) }
#     x(0)       = 40 mm   (fixed; matches the paper's reference)
#     R^v cap    in { 0.05, 0.5, 1.0 }
#
# Total: 3 * 3 * 3 = 27 Storm syntheses.
#
# Wall time:  ~1.5--3 h per cell on the present M3 MDP
#             (1.6e7 reachable states, 6.5e7 transitions);
#             total ~50--80 h sequential -> ~2-3 days under nohup.
#
# Usage:
#     chmod +x run_phi_mo2.sh
#     ./run_phi_mo2.sh --storm /path/to/storm/build/bin/storm           # foreground
#     nohup ./run_phi_mo2.sh --storm /path/to/storm > mo2.log 2>&1 &    # background
#     disown
#
# Resume / force:
#     --resume   (default) skip cells whose .txt already contains a Storm result
#     --force    rerun every cell, overwriting prior outputs
#
###############################################################################

set -euo pipefail

# =================================================================
#                           CONFIGURATION
# =================================================================

# Storm binary (override with --storm or edit here)
STORM_BIN="/path/to/storm/build/bin/storm"

# PRISM model: defaults to ../ relative to this script (one level above
# G1_G3_extension), falls back to a local copy if present.
MODEL_FILE="../models/M3/M3_mdp_synthesis.pm"

# Storm engine + flags
STORM_ENGINE="sparse"

# Output layout
RESULTS_DIR="Results_mo2"
LOG_DIR="Logs_mo2"
CSV_FILE="mo2_results.csv"

# Fixed initial soil moisture (mm)
XINIT="40"

# Factorial axes
SOIL_C=(0.01 0.025 0.05)                # drainage constants
SOIL_NAME=(clay loam sandy_loam)        # names aligned by index with SOIL_C
W_INIT=(0 1 2)                          # weather state indices
W_NAME=(Dry Moderate Wet)               # names aligned by index with W_INIT
RV_CAPS=(0.05) # 0.5 1.0)                  # expected-violation caps

# Resume semantics (idempotent across crashes); default = resume.
RESUME=1
FORCE=0

# =================================================================
#                       COLOURED LOG OUTPUT
# =================================================================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# =================================================================
#                              CLI
# =================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --storm)  STORM_BIN="$2"; shift 2 ;;
        --model)  MODEL_FILE="$2"; shift 2 ;;
        --resume) RESUME=1; FORCE=0; shift ;;
        --force)  FORCE=1; RESUME=0; shift ;;
        --help|-h)
            echo "Usage: $0 [--storm PATH] [--model FILE] [--resume|--force]"
            echo "  --resume   (default) skip cells with a completed .txt"
            echo "  --force    rerun every cell, overwriting prior outputs"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# =================================================================
#                           PATH SETUP
# =================================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$SCRIPT_DIR"

mkdir -p "$PROJECT_DIR/$RESULTS_DIR"
mkdir -p "$PROJECT_DIR/$LOG_DIR"

CSV_PATH="$PROJECT_DIR/$CSV_FILE"

# Resolve model path (allow either absolute or relative-to-script)
if [[ "$MODEL_FILE" != /* ]]; then
    MODEL_FILE_ABS="$( cd "$SCRIPT_DIR" && cd "$( dirname "$MODEL_FILE" )" 2>/dev/null && pwd )/$( basename "$MODEL_FILE" )"
    # Fallback: also try a sibling copy in the script dir
    if [[ ! -f "$MODEL_FILE_ABS" && -f "$SCRIPT_DIR/$( basename "$MODEL_FILE" )" ]]; then
        MODEL_FILE_ABS="$SCRIPT_DIR/$( basename "$MODEL_FILE" )"
    fi
else
    MODEL_FILE_ABS="$MODEL_FILE"
fi

# =================================================================
#                          SANITY CHECKS
# =================================================================
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  phi_mo2: minimise water under R^v cap                     ${NC}"
echo -e "${GREEN}  Factorial: 3 soils x 3 weather x 3 caps = 27 syntheses    ${NC}"
echo -e "${GREEN}  Fixed:    x(0) = ${XINIT} mm                              ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""

[[ -f "$MODEL_FILE_ABS" ]] || { echo -e "${RED}[ERROR] Model not found: $MODEL_FILE_ABS${NC}"; exit 1; }
[[ -x "$STORM_BIN"      ]] || { echo -e "${RED}[ERROR] Storm not executable: $STORM_BIN${NC}"; \
                                echo "  Use: $0 --storm /path/to/storm/build/bin/storm"; exit 1; }

STORM_VER=$("$STORM_BIN" --version 2>&1 | head -1 || true)
echo -e "Storm:  ${CYAN}$STORM_VER${NC}"
echo -e "Model:  $MODEL_FILE_ABS"
echo -e "Soils:  ${SOIL_C[*]}"
echo -e "Weather:${W_INIT[*]}"
echo -e "R^v cap:${RV_CAPS[*]}"
echo ""

# =================================================================
#                          CSV HEADER
# =================================================================
CSV_HEADER="tier,scenario,c,w_init,w_name,xinit,Rv_cap,property,result_water_min,states,transitions,build_sec,check_sec,wall_sec"
if [[ $FORCE -eq 1 || ! -f "$CSV_PATH" ]]; then
    echo "$CSV_HEADER" > "$CSV_PATH"
    echo -e "${CYAN}Created fresh CSV at $CSV_PATH${NC}"
else
    echo -e "${CYAN}Resuming with existing CSV $CSV_PATH ($(($(wc -l < "$CSV_PATH") - 1)) data rows present)${NC}"
fi
echo ""

# =================================================================
#                       HELPER FUNCTIONS
# =================================================================

is_cell_complete() {
    # Returns 0 if the per-cell .txt already contains a Storm result line.
    local txt="$1"
    [[ -f "$txt" ]] && grep -q "Result (for initial states):" "$txt"
}

csv_row_exists() {
    # Returns 0 if the scenario name already appears in the CSV.
    local scen="$1"
    [[ -f "$CSV_PATH" ]] && grep -q ",${scen}," "$CSV_PATH"
}

emit_csv_row_from_txt() {
    # Recover a CSV row from an existing per-cell .txt (used when the cell
    # is complete but its CSV row was missing).
    local c="$1" w_init="$2" w_name="$3" cap="$4" scen="$5" txt="$6"
    local prop='multi(R{"water_usage"}min=? [C<=140], R{"safety_violations"}<='"$cap"' [C<=140])'
    local value states trans build_sec check_sec
    value=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' "$txt" | head -1 || echo "N/A")
    states=$(grep -oP 'States:\s+\K[0-9]+' "$txt" | head -1 || echo "N/A")
    trans=$(grep -oP 'Transitions:\s+\K[0-9]+' "$txt" | head -1 || echo "N/A")
    build_sec=$(grep -oP 'Time for model construction:\s+\K[0-9.]+' "$txt" | head -1 || echo "N/A")
    check_sec=$(grep -oP 'Time for model checking:\s+\K[0-9.]+' "$txt" | head -1 || echo "N/A")
    echo "phi_mo2,${scen},${c},${w_init},${w_name},${XINIT},${cap},\"${prop}\",${value},${states},${trans},${build_sec},${check_sec},0" \
        >> "$CSV_PATH"
}

run_one() {
    # Runs Storm for one (soil, weather, cap) triple, with resume guard.
    local c="$1" w_init="$2" w_name="$3" cap="$4"
    local scen="mo2_c${c}_w${w_init}_x${XINIT}_Rv${cap}"
    local result_file="$PROJECT_DIR/$RESULTS_DIR/${scen}.txt"
    local log_file="$PROJECT_DIR/$LOG_DIR/${scen}.log"

    # ---- RESUME: skip cells already completed --------------------
    if [[ $RESUME -eq 1 && $FORCE -eq 0 ]] && is_cell_complete "$result_file"; then
        if csv_row_exists "$scen"; then
            echo -e "${CYAN}[SKIP]${NC} $scen  (already complete; CSV row present)"
        else
            emit_csv_row_from_txt "$c" "$w_init" "$w_name" "$cap" "$scen" "$result_file"
            echo -e "${CYAN}[SKIP]${NC} $scen  (already complete; CSV row recovered from .txt)"
        fi
        return 0
    fi

    # ---- Patch model: ensure x(0) = XINIT ------------------------
    local temp_model="$PROJECT_DIR/${scen}_temp.pm"
    sed "s/x : \[0\.\.100\] init [0-9]*/x : [0..100] init $XINIT/" \
        "$MODEL_FILE_ABS" > "$temp_model"

    # ---- Build property and run Storm ----------------------------
    local prop='multi(R{"water_usage"}min=? [C<=140], R{"safety_violations"}<='"$cap"' [C<=140])'

    local start_ts; start_ts=$(date +%s)

    if "$STORM_BIN" \
        --prism "$temp_model" \
        --prop "$prop" \
        --constants "c=$c,w_init=$w_init" \
        --engine "$STORM_ENGINE" \
        --prismcompat \
        --statistics \
        > "$result_file" 2> "$log_file"; then

        local end_ts; end_ts=$(date +%s)
        local wall=$(( end_ts - start_ts ))
        local value states trans build_sec check_sec
        value=$(grep -oP 'Result \(for initial states\): \K[0-9.eE+\-]+' "$result_file" | head -1 || echo "N/A")
        states=$(grep -oP 'States:\s+\K[0-9]+' "$result_file" | head -1 || echo "N/A")
        trans=$(grep -oP 'Transitions:\s+\K[0-9]+' "$result_file" | head -1 || echo "N/A")
        build_sec=$(grep -oP 'Time for model construction:\s+\K[0-9.]+' "$result_file" | head -1 || echo "N/A")
        check_sec=$(grep -oP 'Time for model checking:\s+\K[0-9.]+' "$result_file" | head -1 || echo "N/A")

        echo "phi_mo2,${scen},${c},${w_init},${w_name},${XINIT},${cap},\"${prop}\",${value},${states},${trans},${build_sec},${check_sec},${wall}" \
            >> "$CSV_PATH"
        echo -e "${GREEN}[OK]${NC}  ${scen}  R^w_min=${value}  wall=${wall}s ($(( wall / 60 ))m$(( wall % 60 ))s)"
    else
        local end_ts; end_ts=$(date +%s)
        local wall=$(( end_ts - start_ts ))
        echo "phi_mo2,${scen},${c},${w_init},${w_name},${XINIT},${cap},\"${prop}\",FAILED,N/A,N/A,N/A,N/A,${wall}" \
            >> "$CSV_PATH"
        echo -e "${RED}[FAIL]${NC} ${scen}  wall=${wall}s"
        tail -3 "$log_file" 2>/dev/null | sed 's/^/  /'
    fi

    rm -f "$temp_model"
}

# =================================================================
#                           EXECUTE
# =================================================================
for i in "${!SOIL_C[@]}"; do
    c="${SOIL_C[$i]}"
    s="${SOIL_NAME[$i]}"
    for j in "${!W_INIT[@]}"; do
        w="${W_INIT[$j]}"
        wn="${W_NAME[$j]}"
        echo -e "${YELLOW}--- Soil=${s} (c=${c})   Weather=${wn} (w_init=${w}) ---${NC}"
        for cap in "${RV_CAPS[@]}"; do
            run_one "$c" "$w" "$wn" "$cap"
        done
    done
done

# =================================================================
#                           SUMMARY
# =================================================================
TOTAL=$(tail -n +2 "$CSV_PATH" | wc -l)
FAILED=$(grep -c "FAILED" "$CSV_PATH" || true)
OK=$(( TOTAL - FAILED ))

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  phi_mo2 COMPLETE                                          ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "  CSV:       ${CYAN}${CSV_PATH}${NC}"
echo -e "  Succeeded: ${GREEN}${OK}${NC} / 27"
echo -e "  Failed:    ${RED}${FAILED}${NC}"
echo ""
echo "Next: integrate phi_mo2_results.csv into Sec. VIII-E of the manuscript."
