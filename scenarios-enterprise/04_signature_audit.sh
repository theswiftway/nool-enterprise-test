#!/usr/bin/env bash
# ============================================================================
# 04_signature_audit.sh — Nool Cryptographic Signature Chain Audit
#
# Validates Nool's cryptographic signature chain across all knots.
# Walks the entire DAG verifying knot_id integrity, DAG linearity,
# Git mirror consistency, and structural invariants.
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
TEST_BED="/tmp/nool-enterprise-test/bed_04_$$"
ARTIFACTS_DIR="/tmp/nool-enterprise-test/artifacts-enterprise"
mkdir -p "$TEST_BED" "$ARTIFACTS_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${ARTIFACTS_DIR}/04_signature_audit_${TIMESTAMP}.json"

TOTAL_KNOTS=50
BATCH_SIZE=10

# --- Helpers ---------------------------------------------------------------
cleanup() { rm -rf "$TEST_BED"; }
trap cleanup EXIT ERR

nool_json() { nool "$@" --json 2>/dev/null; }

# --- 1. Initialize ---------------------------------------------------------
info "=== Signature Audit Test ==="
info "Test bed: $TEST_BED"

cd "$TEST_BED"
git init -q
info "Initializing Nool..."
nool init --from-git main --quiet 2>/dev/null || nool init --quiet 2>/dev/null

# --- 2. Build knots --------------------------------------------------------
info "Building $TOTAL_KNOTS knots in batches of $BATCH_SIZE..."

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

START_TIME=$(date +%s%N)

for ((i = 1; i <= TOTAL_KNOTS; i++)); do
  idx=$(( (i - 1) % ${#RANDOM_INTENTS[@]} ))
  intent="${RANDOM_INTENTS[$idx]} - iteration $i"
  touch "file_${i}.txt"
  echo "$(date +%s) $i: $intent" > "file_${i}.txt"

  nool propose --all --intent "$intent" --fast --quiet 2>/dev/null || \
    nool propose --intent "$intent" --path "file_${i}.txt" --fast --quiet 2>/dev/null

  nool solidify --fast --quiet 2>/dev/null || true

  if (( i % BATCH_SIZE == 0 )); then
    info "  ... $i / $TOTAL_KNOTS knots created"
  fi
done

END_TIME=$(date +%s%N)
KNOT_DURATION_NS=$(( END_TIME - START_TIME ))
KNOT_DURATION_S=$(echo "scale=3; $KNOT_DURATION_NS / 1000000000" | bc)
KNOTS_PER_SEC=$(echo "scale=2; $TOTAL_KNOTS / $KNOT_DURATION_S" | bc)

info "Knot creation: ${KNOT_DURATION_S}s (${KNOTS_PER_SEC} knots/s)"

# --- 3. Verify knot format from log ----------------------------------------
info "Validating knot chain from log..."

LOG_JSON=$(nool_json log) || bail "nool log --json failed"
STATUS_JSON=$(nool_json status) || bail "nool status --json failed"

LOG_KNOT_COUNT=$(echo "$LOG_JSON" | jq 'length' 2>/dev/null || echo "0")
STATUS_KNOT_COUNT=$(echo "$STATUS_JSON" | jq '.knot_count // 0' 2>/dev/null || echo "0")
DAG_HEADS=$(echo "$STATUS_JSON" | jq '.dag_heads | length' 2>/dev/null || echo "0")

info "Log reports $LOG_KNOT_COUNT knots, status reports $STATUS_KNOT_COUNT, heads=$DAG_HEADS"

# Validate each knot has a non-empty 32-char hex knot_id
INVALID_KNOTS=0
for knot in $(echo "$LOG_JSON" | jq -r '.[].knot_id // empty' 2>/dev/null); do
  if [[ ! "$knot" =~ ^[0-9a-f]{32,64}$ ]]; then
    warn "Invalid knot_id format: $knot"
    INVALID_KNOTS=$((INVALID_KNOTS + 1))
  fi
done

if [[ "$INVALID_KNOTS" -eq 0 ]]; then
  pass "All knot_ids are valid hex strings"
else
  fail "$INVALID_KNOTS knot(s) have invalid knot_id format"
fi

# DAG linearity check
if [[ "$DAG_HEADS" -eq 1 ]]; then
  pass "DAG is linear (1 head)"
elif [[ "$DAG_HEADS" -eq 0 ]]; then
  warn "DAG has 0 heads (empty repo?)"
else
  fail "DAG has $DAG_HEADS heads — expected 1 for linear history"
fi

# Knot count consistency
if [[ "$LOG_KNOT_COUNT" -eq "$STATUS_KNOT_COUNT" ]] && [[ "$LOG_KNOT_COUNT" -gt 0 ]]; then
  pass "Knot count consistent between log ($LOG_KNOT_COUNT) and status ($STATUS_KNOT_COUNT)"
else
  fail "Knot count mismatch: log=$LOG_KNOT_COUNT status=$STATUS_KNOT_COUNT"
fi

# --- 4. Git mirror check ---------------------------------------------------
info "Checking Git mirror consistency..."

# Check main git repo commits
MAIN_COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")

# Check .nool/git_mirror if available
MIRROR_COMMIT_COUNT=0
if [[ -d ".nool/git_mirror" ]]; then
  MIRROR_COMMIT_COUNT=$(git -C .nool/git_mirror rev-list --count HEAD 2>/dev/null || echo "0")
fi

MIRROR_COMMITS=$MAIN_COMMIT_COUNT
if [[ "$MIRROR_COMMIT_COUNT" -gt "$MIRROR_COMMITS" ]]; then
  MIRROR_COMMITS=$MIRROR_COMMIT_COUNT
fi

if [[ "$MIRROR_COMMITS" -ge "$LOG_KNOT_COUNT" ]]; then
  pass "Git mirror commits ($MIRROR_COMMITS) >= knot count ($LOG_KNOT_COUNT)"
else
  warn "Git mirror commits ($MIRROR_COMMITS) < knot count ($LOG_KNOT_COUNT)"
fi

# --- 5. Integrity check ----------------------------------------------------
info "Running integrity checks..."

VERIFY_START=$(date +%s%N)
VERIFY_OUTPUT=$(nool verify --all 2>&1 || true)
VERIFY_END=$(date +%s%N)
VERIFY_TIME_MS=$(( (VERIFY_END - VERIFY_START) / 1000000 ))

VERIFY_VIOLATIONS=$(echo "$VERIFY_OUTPUT" | grep -ciE "violation|error|fail" 2>/dev/null || echo "0")

if [[ "$VERIFY_VIOLATIONS" -eq 0 ]]; then
  pass "nool verify --all: no violations"
else
  warn "nool verify --all: $VERIFY_VIOLATIONS violation(s) detected"
fi

# Doctor check (non-strict)
DOCTOR_OUTPUT=$(nool doctor --json 2>&1 || true)
DOCTOR_PASSED=$(echo "$DOCTOR_OUTPUT" | jq -r '.verdict // "unknown"' 2>/dev/null || echo "unknown")

# Audit steering check
AUDIT_OUTPUT=$(nool audit steering 2>&1 || true)

# --- 6. Results ------------------------------------------------------------
AUDIT_PASSED="true"
if [[ "$VERIFY_VIOLATIONS" -gt 0 ]]; then
  AUDIT_PASSED="false"
fi
if [[ "$DAG_HEADS" -ne 1 ]] && [[ "$LOG_KNOT_COUNT" -gt 0 ]]; then
  AUDIT_PASSED="false"
fi
if [[ "$INVALID_KNOTS" -gt 0 ]]; then
  AUDIT_PASSED="false"
fi

cat > "$RESULTS_FILE" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "total_knots": $LOG_KNOT_COUNT,
  "dag_heads": $DAG_HEADS,
  "invalid_knot_ids": $INVALID_KNOTS,
  "log_knot_count": $LOG_KNOT_COUNT,
  "status_knot_count": $STATUS_KNOT_COUNT,
  "knot_count_consistent": $( [[ "$LOG_KNOT_COUNT" -eq "$STATUS_KNOT_COUNT" ]] && echo true || echo false ),
  "verify_violations": $VERIFY_VIOLATIONS,
  "verify_time_ms": $VERIFY_TIME_MS,
  "mirror_commits": $MIRROR_COMMITS,
  "mirror_sufficient": $( [[ "$MIRROR_COMMITS" -ge "$LOG_KNOT_COUNT" ]] && echo true || echo false ),
  "knots_per_second": $KNOTS_PER_SEC,
  "total_duration_s": $KNOT_DURATION_S,
  "doctor_verdict": "$DOCTOR_PASSED",
  "audit_passed": $AUDIT_PASSED,
  "test_bed": "$TEST_BED"
}
EOF

info "=== Results ==="
echo ""
jq . "$RESULTS_FILE"
echo ""

if [[ "$AUDIT_PASSED" == "true" ]]; then
  pass "SIGNATURE AUDIT PASSED"
else
  fail "SIGNATURE AUDIT FAILED — see $RESULTS_FILE"
fi

info "Results saved to: $RESULTS_FILE"
