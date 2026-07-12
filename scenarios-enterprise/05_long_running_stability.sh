#!/usr/bin/env bash
# ============================================================================
# 05_long_running_stability.sh — Nool Long-Running Stability Test
#
# Simulates 24h of continuous Nool operations compressed to ~5min using
# batch operations. Runs cycles of propose+solidify, monitors system
# health, and measures ledger growth.
# ============================================================================
set -euo pipefail

# --- Colors & helpers -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} ${BOLD}$*${NC}"; }
pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }
bail()  { fail "$*"; exit 1; }

# --- Config ----------------------------------------------------------------
TEST_BED="/tmp/nool-enterprise-test/bed_05_$$"
ARTIFACTS_DIR="/tmp/nool-enterprise-test/artifacts-enterprise"
mkdir -p "$TEST_BED" "$ARTIFACTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${ARTIFACTS_DIR}/05_long_running_${TIMESTAMP}.json"

TOTAL_BATCHES=6
KNOTS_PER_BATCH=50
TOTAL_KNOTS=$(( TOTAL_BATCHES * KNOTS_PER_BATCH ))

# --- Helpers ---------------------------------------------------------------
cleanup() { rm -rf "$TEST_BED"; }
trap cleanup EXIT ERR

nool_json() { nool "$@" --json 2>/dev/null; }

measure_dir_kb() {
  du -sk "$1" 2>/dev/null | awk '{print $1}'
}

# --- 1. Initialize ---------------------------------------------------------
info "=== Long-Running Stability Test ==="
info "Test bed: $TEST_BED"
info "Simulating 24h of operations ($TOTAL_BATCHES batches x $KNOTS_PER_BATCH ops)"

cd "$TEST_BED"
git init -q
nool init --from-git main --quiet 2>/dev/null || nool init --quiet 2>/dev/null

START_DIR_SIZE=$(measure_dir_kb .nool)
info "Initial .nool/ size: ${START_DIR_SIZE}KB"

RANDOM_INTENTS=(
  "Add rate limiting middleware"
  "Refactor database connection pool"
  "Update API documentation"
  "Fix null pointer in auth handler"
  "Add integration tests for payment flow"
  "Optimize query caching layer"
  "Update dependencies to latest"
  "Add input validation for user service"
  "Refactor logging infrastructure"
  "Add health check endpoint"
  "Fix race condition in scheduler"
  "Update deployment configuration"
  "Add metrics collection pipeline"
  "Refactor error handling in API"
  "Add backup strategy for storage"
  "Update CI/CD pipeline config"
  "Fix memory leak in stream processor"
  "Add rate limit headers to response"
  "Refactor notification service"
  "Update SSL certificate handling"
  "Add feature flags infrastructure"
  "Fix off-by-one in pagination"
  "Add data migration scripts"
  "Refactor authentication middleware"
  "Update monitoring alerts"
  "Add circuit breaker pattern"
  "Fix encoding issue in CSV export"
  "Add request tracing middleware"
  "Refactor configuration management"
  "Update database migration strategy"
  "Add cross-origin resource sharing"
  "Fix timeout in external API calls"
  "Add compression middleware"
  "Refactor background job processor"
  "Update audit logging system"
  "Add retry logic for network calls"
  "Fix content negotiation headers"
  "Add client-side caching headers"
  "Refactor session management"
  "Update webhook delivery system"
  "Add distributed tracing"
  "Fix serialization edge case"
  "Add payload validation middleware"
  "Refactor queue message handling"
  "Update search indexing pipeline"
  "Add health check aggregation"
  "Fix OAuth token refresh flow"
  "Add request deduplication"
  "Refactor template rendering"
  "Update feature toggle system"
)

# Track metrics across all batches
PREV_KNOT_COUNT=0
KNOT_GROWTH=()
BATCH_TIMES=()
OVERALL_START=$(date +%s%N)

# --- 2. Run batches --------------------------------------------------------
for ((batch = 1; batch <= TOTAL_BATCHES; batch++)); do
  info "=== Batch $batch / $TOTAL_BATCHES ($KNOTS_PER_BATCH ops) ==="

  # Pre-batch health snapshot
  PRE_STATUS=$(nool_json status || echo '{}')
  PRE_KNOT_COUNT=$(echo "$PRE_STATUS" | jq '.knot_count // 0' 2>/dev/null || echo "0")
  PRE_PENDING=$(echo "$PRE_STATUS" | jq '.pending_candidates // 0' 2>/dev/null || echo "0")
  PRE_MEM=$(ps -p $$ -o rss= 2>/dev/null || echo "0")

  BATCH_START=$(date +%s%N)

  # Create batch of knots
  for ((k = 1; k <= KNOTS_PER_BATCH; k++)); do
    global_idx=$(( (batch - 1) * KNOTS_PER_BATCH + k ))
    idx=$(( (global_idx - 1) % ${#RANDOM_INTENTS[@]} ))
    intents="${RANDOM_INTENTS[$idx]} - batch $batch op $k"

    touch "op_${global_idx}.txt"
    echo "batch=$batch op=$k ts=$(date +%s)" > "op_${global_idx}.txt"
    nool propose --all --intent "$intents" --fast --quiet 2>/dev/null || \
      nool propose --intent "$intents" --path "op_${global_idx}.txt" --fast --quiet 2>/dev/null
    nool solidify --fast --quiet 2>/dev/null || true
  done

  BATCH_END=$(date +%s%N)
  BATCH_DURATION_S=$(echo "scale=3; ($BATCH_END - $BATCH_START) / 1000000000" | bc)
  BATCH_TIMES+=("$BATCH_DURATION_S")

  # --- Per-batch health check ----------------------------------------------
  POST_STATUS=$(nool_json status || echo '{}')
  POST_KNOT_COUNT=$(echo "$POST_STATUS" | jq '.knot_count // 0' 2>/dev/null || echo "0")
  POST_PENDING=$(echo "$POST_STATUS" | jq '.pending_candidates // 0' 2>/dev/null || echo "0")
  DAG_HEADS=$(echo "$POST_STATUS" | jq '.dag_heads | length' 2>/dev/null || echo "0")
  POST_MEM=$(ps -p $$ -o rss= 2>/dev/null || echo "0")

  KNOT_GROWTH+=("$POST_KNOT_COUNT")

  # Check for errors in status
  ERRORS=$(echo "$POST_STATUS" | jq '.. | objects | select(.error != null) | .error' 2>/dev/null || true)

  info "  Knots: $PRE_KNOT_COUNT → $POST_KNOT_COUNT | Pending: $PRE_PENDING → $POST_PENDING"
  info "  DAG heads: $DAG_HEADS | Batch time: ${BATCH_DURATION_S}s"
  info "  Memory: RSS ${PRE_MEM}KB → ${POST_MEM}KB"

  if [[ -n "$ERRORS" ]]; then
    warn "  Errors detected: $ERRORS"
  else
    pass "  No errors"
  fi

  # Verify DAG linearity each batch
  if [[ "$DAG_HEADS" -eq 0 ]] && [[ "$POST_KNOT_COUNT" -eq 0 ]]; then
    warn "  Empty DAG (first batch may still be initializing)"
  elif [[ "$DAG_HEADS" -ne 1 ]]; then
    fail "  DAG has $DAG_HEADS heads — expected 1!"
  else
    pass "  DAG is linear"
  fi

  info "  Batch $batch complete in ${BATCH_DURATION_S}s"
  echo ""

  # Brief pause between batches to let system settle
  sleep 0.5
done

OVERALL_END=$(date +%s%N)
OVERALL_DURATION_S=$(echo "scale=3; ($OVERALL_END - $OVERALL_START) / 1000000000" | bc)

# --- 3. Final verification -------------------------------------------------
info "=== Final Verification ==="

FINAL_STATUS=$(nool_json status || echo '{}')
FINAL_KNOT_COUNT=$(echo "$FINAL_STATUS" | jq '.knot_count // 0' 2>/dev/null || echo "0")
FINAL_DAG_HEADS=$(echo "$FINAL_STATUS" | jq '.dag_heads | length' 2>/dev/null || echo "0")
FINAL_PENDING=$(echo "$FINAL_STATUS" | jq '.pending_candidates // 0' 2>/dev/null || echo "0")

# Full verify
VERIFY_OUTPUT=$(nool verify --all 2>&1 || true)
VERIFY_VIOLATIONS=$(echo "$VERIFY_OUTPUT" | grep -ciE "violation|error|fail" 2>/dev/null || echo "0")
VERIFY_PASSED=$([[ "$VERIFY_VIOLATIONS" -eq 0 ]] && echo true || echo false)

# Log check for completeness
LOG_JSON=$(nool_json log || echo '[]')
LOG_COUNT=$(echo "$LOG_JSON" | jq 'length' 2>/dev/null || echo "0")

# DAG linearity
DAG_LINEAR=$([[ "$FINAL_DAG_HEADS" -eq 1 ]] && echo true || echo false)

# Memory metrics
FINAL_MEM=$(ps -p $$ -o rss= 2>/dev/null || echo "0")
START_MEM=$(ps -p $$ -o rss= 2>/dev/null || echo "0")  # approximated

# Dir size
END_DIR_SIZE=$(measure_dir_kb .nool)
DIR_GROWTH_KB=$(( END_DIR_SIZE - START_DIR_SIZE ))

# --- 4. Compute metrics ----------------------------------------------------
info "=== Stability Metrics ==="
info "Total operations: $TOTAL_KNOTS"
info "Total time: ${OVERALL_DURATION_S}s"
info "Growth rate: $(echo "scale=2; $TOTAL_KNOTS / $OVERALL_DURATION_S" | bc) ops/s"
info "Dir growth: ${START_DIR_SIZE}KB → ${END_DIR_SIZE}KB (${DIR_GROWTH_KB}KB)"
info "Final knot count: $FINAL_KNOT_COUNT (log: $LOG_COUNT)"
info "DAG heads: $FINAL_DAG_HEADS | Linear: $DAG_LINEAR"
info "Verify violations: $VERIFY_VIOLATIONS | Passed: $VERIFY_PASSED"

# Aggregate batch stats
TOTAL_BATCH_TIME=$(printf "%s\n" "${BATCH_TIMES[@]}" | awk '{s+=$1} END {print s}')
AVG_BATCH_TIME=$(printf "%s\n" "${BATCH_TIMES[@]}" | awk '{if(NR>0){s+=$1;c++}} END {if(c>0) print s/c; else print 0}')

cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "total_batches": $TOTAL_BATCHES,
  "knots_per_batch": $KNOTS_PER_BATCH,
  "target_total_knots": $TOTAL_KNOTS,
  "final_knot_count": $FINAL_KNOT_COUNT,
  "log_knot_count": $LOG_COUNT,
  "knot_count_match": $( [[ "$FINAL_KNOT_COUNT" -eq "$LOG_COUNT" ]] && echo true || echo false ),
  "dag_heads": $FINAL_DAG_HEADS,
  "dag_linear": $DAG_LINEAR,
  "verify_passed": $VERIFY_PASSED,
  "verify_violations": $VERIFY_VIOLATIONS,
  "final_pending_candidates": $FINAL_PENDING,
  "start_dir_size_kb": $START_DIR_SIZE,
  "end_dir_size_kb": $END_DIR_SIZE,
  "dir_growth_kb": $DIR_GROWTH_KB,
  "total_duration_s": $OVERALL_DURATION_S,
  "avg_batch_time_s": $AVG_BATCH_TIME,
  "total_batch_time_s": $TOTAL_BATCH_TIME,
  "throughput_ops_per_sec": $(echo "scale=2; $FINAL_KNOT_COUNT / $OVERALL_DURATION_S" | bc 2>/dev/null || echo "0"),
  "batch_times_s": [$(printf "%s" "${BATCH_TIMES[*]}" | sed 's/ /, /g')],
  "batch_knot_cumulative": [$(printf "%s" "${KNOT_GROWTH[*]}" | sed 's/ /, /g')],
  "test_bed": "$TEST_BED"
}
EOF

echo ""
if [[ "$VERIFY_PASSED" == "true" ]] && [[ "$DAG_LINEAR" == "true" ]]; then
  pass "LONG-RUNNING STABILITY TEST PASSED"
else
  fail "LONG-RUNNING STABILITY TEST HAS ISSUES"
  [[ "$VERIFY_PASSED" == "false" ]] && fail "  - Verify failed ($VERIFY_VIOLATIONS violations)"
  [[ "$DAG_LINEAR" == "false" ]] && fail "  - DAG is not linear ($FINAL_DAG_HEADS heads)"
fi

info "Results saved to: $RESULTS_FILE"
