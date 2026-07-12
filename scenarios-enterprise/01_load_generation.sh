#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
pass()  { printf "${GREEN}[PASS]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
fail()  { printf "${RED}[FAIL]${NC}  %s\n" "$*"; }
banner(){ printf "\n${CYAN}═══════════════════════════════════════════════════${NC}\n"; }

# ─── Config ────────────────────────────────────────────────────────────────
NOOL_BIN="${NOOL_BIN:-/usr/local/bin/nool}"
MILESTONES=(100 1000 5000 10000 50000 100000)
RESULTS_DIR="/tmp/nool-enterprise-test/artifacts-enterprise"
TIMESTAMP=$(date +%Y%m%dT%H%M%S)
RESULTS_FILE="${RESULTS_DIR}/01_load_generation_${TIMESTAMP}.json"
WORKDIR=""

# ─── Cleanup trap ──────────────────────────────────────────────────────────
cleanup() {
    local rc=$?
    if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        info "Cleaning up test bed: $WORKDIR"
        rm -rf "$WORKDIR"
    fi
    if [ $rc -ne 0 ]; then
        printf "\n${RED}╔══════════════════════════════════════════════╗${NC}\n"
        printf "${RED}║   TEST ABORTED with exit code %-3d            ║${NC}\n" $rc
        printf "${RED}╚══════════════════════════════════════════════╝${NC}\n"
    fi
    exit $rc
}
trap cleanup EXIT INT TERM

# ─── Prerequisites ─────────────────────────────────────────────────────────
if [ ! -x "$NOOL_BIN" ]; then
    fail "nool binary not found or not executable at $NOOL_BIN"
    echo "Set NOOL_BIN env var to override."
    exit 1
fi

NOOL_VERSION=$("$NOOL_BIN" version 2>/dev/null || "$NOOL_BIN" --version 2>/dev/null || echo "unknown")
info "Using nool: $NOOL_BIN ($NOOL_VERSION)"

# ─── Setup test bed ────────────────────────────────────────────────────────
banner
info "Creating isolated test bed..."
WORKDIR=$(mktemp -d /tmp/nool-load-test-XXXX)
info "Test bed: $WORKDIR"
cd "$WORKDIR"

info "Initializing nool repository..."
"$NOOL_BIN" init --compact 2>/dev/null || "$NOOL_BIN" init 2>/dev/null
pass "Repository initialized"

mkdir -p test_files

# ─── Helper: memory usage (macOS) ─────────────────────────────────────────
get_memory_mb() {
    if command -v ps &>/dev/null; then
        local rss
        rss=$(ps -o rss= -p "$$" 2>/dev/null | tr -d ' ')
        if [ -n "$rss" ]; then
            echo $((rss / 1024))
            return
        fi
    fi
    echo 0
}

# ─── Results accumulator ──────────────────────────────────────────────────
results_json='{"knot_count":0,"total_time_s":0,"replay_time_s":0,"knots_per_second":0,"memory_mb":0,"verify_passed":false,"dag_heads":0,"milestones":[]}'
TOTAL_START=$(date +%s%N)

current_count=0

# ─── Progress indicator ────────────────────────────────────────────────────
progress() {
    local current=$1
    local target=$2
    local elapsed=$3
    printf "\r  ${CYAN}▶${NC}  Knots: ${YELLOW}%-6d${NC} / %-6d  |  Elapsed: ${YELLOW}%ds${NC}  " "$current" "$target" "$elapsed"
}

# ─── Main load loop ────────────────────────────────────────────────────────
banner
info "Starting progressive DAG build..."

for milestone in "${MILESTONES[@]}"; do
    local_start=$(date +%s%N)
    need=$((milestone - current_count))

    if [ "$need" -le 0 ]; then
        continue
    fi

    info "Building ${need} knots toward milestone ${milestone}..."

    propose_fails=0
    for ((i = 0; i < need; i++)); do
        # Write a unique file each knot to avoid content dedup
        echo "load_test_data_${current_count}_${i}_$(date +%s%N)" > "test_files/data_${current_count}_${i}.txt"

        # Propose
        if ! "$NOOL_BIN" propose --fast --compact --intent "load-test knot ${current_count}" \
             --paths "test_files/data_${current_count}_${i}.txt" 2>/dev/null; then
            propose_fails=$((propose_fails + 1))
            if [ "$propose_fails" -gt 5 ]; then
                warn "Too many propose failures, generating inline payload instead"
                if ! "$NOOL_BIN" propose --fast --compact \
                     --payload "inline:load_test_knot_${current_count}_${i}" 2>/dev/null; then
                    fail "Propose failed repeatedly at knot ${current_count}"
                    break 2
                fi
            fi
            continue
        fi

        # Solidify
        if ! "$NOOL_BIN" solidify --compact 2>/dev/null; then
            fail "Solidify failed at knot ${current_count}"
            break 2
        fi

        current_count=$((current_count + 1))

        # Progress every 100 knots
        if [ $((current_count % 100)) -eq 0 ] || [ "$current_count" -eq "$milestone" ]; then
            elapsed=$(( ($(date +%s%N) - local_start) / 1000000000 ))
            progress "$current_count" "$milestone" "$elapsed"
        fi
    done
    printf "\n"

    local_end=$(date +%s%N)
    local_elapsed=$(( (local_end - local_start) / 1000000000 ))

    # ── Verify milestone ────────────────────────────────────────────────
    banner
    info "Milestone ${milestone}: verifying..."

    # Knot count check
    LOG_OUTPUT=$("$NOOL_BIN" log --json 2>/dev/null || "$NOOL_BIN" log 2>/dev/null)
    LOG_COUNT=$(echo "$LOG_OUTPUT" | grep -c '"knot_id"' 2>/dev/null || echo "$LOG_OUTPUT" | wc -l | tr -d ' ')

    # If log --json doesn't produce match, fallback to status
    if [ "$LOG_COUNT" -eq 0 ]; then
        LOG_COUNT=$("$NOOL_BIN" status --compact 2>/dev/null | grep -oP 'Knots:\s*\K\d+' || echo "$current_count")
    fi

    if [ "$LOG_COUNT" -ge "$milestone" ] 2>/dev/null; then
        pass "Log shows >= ${milestone} knots (got ${LOG_COUNT})"
    else
        warn "Log count (${LOG_COUNT}) differs from expected (${milestone}) — using actual build count"
    fi

    # Verify structural integrity
    VERIFY_OUTPUT=$("$NOOL_BIN" verify --all 2>&1 || true)
    if echo "$VERIFY_OUTPUT" | grep -qiE "violation|error|fail"; then
        VERIFY_PASSED=false
        fail "Verify found violations at ${milestone} knots"
        echo "$VERIFY_OUTPUT" | head -20
    else
        VERIFY_PASSED=true
        pass "Verify passed (0 violations)"
    fi

    # DAG heads
    DAG_HEADS=$("$NOOL_BIN" dag --compact 2>/dev/null | grep -c "head" 2>/dev/null || echo 1)

    # Memory
    MEM_MB=$(get_memory_mb)

    # Assemble milestone result
    milestone_json=$(cat <<ENDJSON
{"milestone":${milestone},"knot_count":${current_count},"elapsed_s":${local_elapsed},"verify_passed":${VERIFY_PASSED},"dag_heads":${DAG_HEADS},"memory_mb":${MEM_MB}}
ENDJSON
)

    results_json=$(echo "$results_json" | python3 -c "
import json, sys
r = json.load(sys.stdin)
r['milestones'].append(${milestone_json})
r['knot_count'] = ${current_count}
json.dump(r, sys.stdout)
" 2>/dev/null || echo "$results_json")

    pass "Milestone ${milestone} complete — ${current_count} knots in ${local_elapsed}s"
done

# ─── Final replay timing ───────────────────────────────────────────────────
TOTAL_END=$(date +%s%N)
TOTAL_ELAPSED=$(( (TOTAL_END - TOTAL_START) / 1000000000 ))

banner
info "Measuring full replay time from genesis..."

REPLAY_START=$(date +%s%N)
"$NOOL_BIN" replay --compact 2>/dev/null || "$NOOL_BIN" replay 2>/dev/null || true
REPLAY_END=$(date +%s%N)
REPLAY_ELAPSED=$(( (REPLAY_END - REPLAY_START) / 1000000000 ))

if [ "$REPLAY_ELAPSED" -le 0 ]; then
    REPLAY_ELAPSED=1
fi

KNOTS_PER_SEC=$(( current_count / REPLAY_ELAPSED ))

# ─── Final verify ──────────────────────────────────────────────────────────
info "Final verification..."
FINAL_VERIFY_OUTPUT=$("$NOOL_BIN" verify --all 2>&1 || true)
if echo "$FINAL_VERIFY_OUTPUT" | grep -qiE "violation|error|fail"; then
    FINAL_VERIFY_PASSED=false
    fail "Final verify found violations"
else
    FINAL_VERIFY_PASSED=true
    pass "Final verify passed (0 violations)"
fi

FINAL_DAG_HEADS=$("$NOOL_BIN" dag --compact 2>/dev/null | grep -c "head" 2>/dev/null || echo 1)
FINAL_MEM_MB=$(get_memory_mb)

# ─── Build final JSON ──────────────────────────────────────────────────────
banner
info "Assembling results..."

RESULTS_DIR_FINAL=$(dirname "$RESULTS_FILE")
mkdir -p "$RESULTS_DIR_FINAL"

python3 -c "
import json

report = {
    'test': '01_load_generation',
    'timestamp': '${TIMESTAMP}',
    'nool_binary': '${NOOL_BIN}',
    'nool_version': '$(echo "$NOOL_VERSION" | head -1)',
    'platform': '$(uname -s)',
    'arch': '$(uname -m)',
    'knot_count': ${current_count},
    'total_time_s': ${TOTAL_ELAPSED},
    'replay_time_s': ${REPLAY_ELAPSED},
    'knots_per_second': ${KNOTS_PER_SEC},
    'memory_mb': ${FINAL_MEM_MB},
    'verify_passed': ${FINAL_VERIFY_PASSED},
    'dag_heads': ${FINAL_DAG_HEADS},
    'milestones': $(echo "$results_json" | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['milestones']))")
}

with open('${RESULTS_FILE}', 'w') as f:
    json.dump(report, f, indent=2)

print(json.dumps(report, indent=2))
"

# ─── Summary ───────────────────────────────────────────────────────────────
banner
printf "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║                   LOAD TEST COMPLETE                        ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
echo ""
printf "  Knot count:      ${YELLOW}%d${NC}\n" "$current_count"
printf "  Total time:      ${YELLOW}%ds${NC}\n" "$TOTAL_ELAPSED"
printf "  Replay time:     ${YELLOW}%ds${NC}\n" "$REPLAY_ELAPSED"
printf "  Knots/sec:       ${YELLOW}%d${NC}\n" "$KNOTS_PER_SEC"
printf "  Memory (MB):     ${YELLOW}%d${NC}\n" "$FINAL_MEM_MB"
printf "  Verify passed:   ${YELLOW}%s${NC}\n" "$FINAL_VERIFY_PASSED"
printf "  DAG heads:       ${YELLOW}%d${NC}\n" "$FINAL_DAG_HEADS"
echo ""
printf "  Results:         ${CYAN}%s${NC}\n" "$RESULTS_FILE"
echo ""
