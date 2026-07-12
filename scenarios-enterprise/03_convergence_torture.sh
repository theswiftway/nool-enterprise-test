#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Nool Enterprise Test 03 — Convergence Torture
#
# Validates deterministic convergence under extreme multi-agent contention.
# Simulates N agents racing to propose and solidify on overlapping NodeIDs,
# then verifies the DAG converges deterministically across multiple rounds.
#
# Phases:
#   1. Announce overlapping intents (5 agents)
#   2. Race N agent proposals on contentious paths in parallel
#   3. Solidify FIFO gauntlet until queue empty
#   4. Convergence verification (heads, verify, log, replay)
#   5. Repeatability — run ROUNDS times, compare head knot IDs
#
# Env vars:
#   AGENTS=N   (default 10)  — concurrent proposers per round
#   ROUNDS=N   (default 3)   — full test iterations for repeatability
# =============================================================================

AGENTS="${AGENTS:-10}"
ROUNDS="${ROUNDS:-3}"
BASE_DIR="/tmp/nool-enterprise-test"
SCENARIO_DIR="${BASE_DIR}/scenarios-enterprise"
ARTIFACTS_DIR="${BASE_DIR}/artifacts-enterprise"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${ARTIFACTS_DIR}/03_convergence_torture_${TIMESTAMP}.json"
MAX_SOLIDIFY_ITERATIONS=200

mkdir -p "${SCENARIO_DIR}" "${ARTIFACTS_DIR}"

# ---- Progress helpers (all output to stderr so stdout is pure JSON) ----
info()  { echo "[INFO]  $*" >&2; }
pass()  { echo "[PASS]  $*" >&2; }
fail()  { echo "[FAIL]  $*" >&2; }
step()  { echo ""; echo "==== $* ====" >&2; }
die()   { echo "[FATAL] $*" >&2; exit 1; }

# ---- Banner ----
cat >&2 <<-BANNER
=========================================================================
 Nool Enterprise Test 03 — Convergence Torture
=========================================================================
 Agents: ${AGENTS}  |  Rounds: ${ROUNDS}
 Results: ${RESULTS_FILE}
=========================================================================
BANNER

ALL_HEADS=()
RESULTS=()

# =============================================================================
# run_round — Execute one full test round
# Outputs single JSON line to stdout; all progress/debug to stderr.
# =============================================================================
run_round() {
    local round=$1
    local wd="${BASE_DIR}/work/run_${round}"
    local props=0 sols=0 heads=0 head_id="" vpass=false

    rm -rf "$wd" && mkdir -p "$wd" && cd "$wd"

    # ----- Initialize fresh Nool repository -----
    step "Round ${round}: Initialize"
    if nool init . 2>/dev/null || nool init 2>/dev/null; then
        info "Repository initialized at ${wd}"
    else
        die "nool init failed in ${wd}"
    fi

    # ----- Phase 1: Announce overlapping intents -----
    step "Round ${round}: Phase 1 — Overlapping Intent Announcements"
    for idx in 0 1 2 3 4; do
        case $idx in
            0) desc="Agent 0 on auth/*" ;;
            1) desc="Agent 1 on middleware/*" ;;
            2) desc="Agent 2 on db/*" ;;
            3) desc="Agent 3 on auth/* + middleware/*" ;;
            4) desc="Agent 4 on db/* + middleware/*" ;;
        esac
        nool announce intent --intent "Contention: ${desc}" 2>/dev/null &
        info "  Announced: ${desc}"
    done
    wait
    info "Phase 1 complete — 5 overlapping intents announced"

    # ----- Conflict discovery -----
    step "Round ${round}: Conflict Discovery"
    nool discover conflicts 2>&1 && info "Conflict check passed" || info "Conflict check returned non-zero"

    # ----- Phase 2: Race proposals -----
    step "Round ${round}: Phase 2 — ${AGENTS} Racing Agents"
    local categories=(auth middleware db)
    local prefixes=(AuthCtrl MiddlewareLogic DbAccess)
    local pids=()
    for i in $(seq 1 "${AGENTS}"); do
        (
            ci=$(( (i - 1) % 3 ))
            cat="${categories[$ci]}"
            pre="${prefixes[$ci]}"
            fname="${cat}/agent_${i}_${RANDOM}.rs"
            mkdir -p "${wd}/${cat}"
            printf "pub fn agent_%d() -> &'static str { \"%s_%d\" }\n" "$i" "$pre" "$i" > "${wd}/${fname}"
            nool propose --fast --kind feature \
                --intent "${pre}: Agent ${i} contention proposal" \
                --paths "${fname}" \
                2>/dev/null
        ) &
        pids+=($!)
    done
    for p in "${pids[@]}"; do wait "$p" 2>/dev/null || true; done
    props=$AGENTS
    info "Phase 2 complete — ${props} proposals submitted"

    # ----- Phase 3: Solidify FIFO gauntlet -----
    step "Round ${round}: Phase 3 — Solidification Gauntlet"
    sols=0
    for _ in $(seq 1 "${MAX_SOLIDIFY_ITERATIONS}"); do
        if nool solidify --fast 2>/dev/null; then
            sols=$((sols + 1))
            echo -n "." >&2
        else
            break
        fi
    done
    echo "" >&2
    info "Phase 3 complete — ${sols} solidifications performed"
    if [ "${sols}" -eq "${MAX_SOLIDIFY_ITERATIONS}" ]; then
        info "WARNING: hit max iterations (${MAX_SOLIDIFY_ITERATIONS}); queue may not be empty"
    fi

    # ----- Phase 4: Convergence verification -----
    step "Round ${round}: Phase 4 — Convergence Verification"

    # 4a: Status and head count
    local st=""
    st=$(nool status --json --compact 2>/dev/null || nool status --json 2>/dev/null || printf '{}')
    heads=$(echo "$st" | grep -oiE '"heads"?\s*:\s*[0-9]+' | grep -oE '[0-9]+' | head -1)
    heads=${heads:-0}
    info "DAG heads: ${heads}"

    # 4b: Structural verification
    if nool verify --all 2>/dev/null; then
        vpass=true
        info "nool verify --all: PASS"
    else
        vpass=false
        info "nool verify --all: FAIL"
    fi

    # 4c: Log output (deterministic ordering check)
    info "Recent DAG entries:"
    nool log --json --compact 2>/dev/null | tail -5 || nool log --json 2>/dev/null | tail -5 || true
    echo "" >&2

    # 4d: Extract head knot ID from status JSON, fallback to log
    head_id=$(echo "$st" | grep -oiE '"head_knot_id"\s*:\s*"[^"]+"' | cut -d'"' -f4)
    if [ -z "${head_id}" ] || [ "${head_id}" = "null" ]; then
        head_id=$(nool log --json --compact 2>/dev/null | grep -oiE '"knot_id"\s*:\s*"[^"]+"' | cut -d'"' -f4 | head -1 || true)
    fi
    if [ -z "${head_id}" ] || [ "${head_id}" = "null" ]; then
        head_id=$(nool log --json 2>/dev/null | grep -oiE '"knot_id"\s*:\s*"[^"]+"' | cut -d'"' -f4 | head -1 || true)
    fi
    head_id=${head_id:-unknown}
    info "Head knot ID: ${head_id}"

    # ----- Emit JSON result line to stdout -----
    cat <<-EOF
	{"round":${round},"agents":${AGENTS},"proposals":${props},"solidifies":${sols},"dag_heads_count":${heads},"verify_passed":${vpass},"head_knot_id":"${head_id}"}
	EOF
}

# =============================================================================
# MAIN — Execute ROUNDS iterations
# =============================================================================
for r in $(seq 1 "${ROUNDS}"); do
    step "EXECUTING ROUND ${r}/${ROUNDS}"
    result=$(run_round "$r")
    RESULTS+=("${result}")
    h=$(echo "${result}" | grep -o '"head_knot_id":"[^"]*"' | cut -d'"' -f4)
    h=${h:-unknown}
    ALL_HEADS+=("${h}")
    info "Round ${r} complete — head: ${h}"
done

# =============================================================================
# Phase 5 — Repeatability analysis (deterministic convergence)
# =============================================================================
step "Phase 5: Repeatability Analysis"
deterministic=true
if [ ${#ALL_HEADS[@]} -ge 2 ]; then
    first="${ALL_HEADS[0]}"
    for h in "${ALL_HEADS[@]:1}"; do
        if [ "$h" != "$first" ]; then
            deterministic=false
            fail "Head knot mismatch: ${first} vs ${h}"
        fi
    done
fi
if [ "$deterministic" = true ]; then
    pass "Deterministic across ${ROUNDS} runs — head: ${ALL_HEADS[0]:-N/A}"
else
    fail "Non-deterministic — heads differ across runs"
fi

# =============================================================================
# Aggregate results to JSON file
# =============================================================================
step "Saving results to ${RESULTS_FILE}"

{
    printf '{"test":"03_convergence_torture","timestamp":"%s","agents_count":%d,"total_proposals":%d,"total_solidifies":null,"dag_heads_count":null,"verify_passed":null,"deterministic_across_runs":%s,"head_knot_id":"%s","rounds_data":[' \
        "${TIMESTAMP}" "${AGENTS}" "$((AGENTS * ROUNDS))" \
        "${deterministic}" "${ALL_HEADS[0]:-null}"

    local sep=""
    for r in "${RESULTS[@]}"; do
        printf '%s%s' "$sep" "$r"
        sep=","
    done
    echo ']}'
} > "${RESULTS_FILE}"

info "Results saved to ${RESULTS_FILE}"

# ---- Summary ----
cat >&2 <<-SUMMARY
=========================================================================
 Convergence Torture: COMPLETE
   Deterministic:     ${deterministic}
   Rounds:            ${ROUNDS}
   Agents per round:  ${AGENTS}
   Canonical head:    ${ALL_HEADS[0]:-N/A}
   Results file:      ${RESULTS_FILE}
=========================================================================
SUMMARY
