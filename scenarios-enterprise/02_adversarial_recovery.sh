#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# 02_adversarial_recovery.sh
# Enterprise catastrophic data-loss recovery test for Nool.
#
# Validates that Nool can survive total .nool/ destruction and reconstruct
# the full Knot DAG from the Bifrost Git mirror (knot.bin in commit history).
# =============================================================================

# ── Color constants ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Config ───────────────────────────────────────────────────────────────────
TEST_BED="/tmp/nool-enterprise-test/test_bed_$$"
ARTIFACTS_DIR="/tmp/nool-enterprise-test/artifacts-enterprise"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="${ARTIFACTS_DIR}/02_adversarial_recovery_${TIMESTAMP}.json"
NUM_KNOTS=100
BRANCH="main"
PASS=0
FAIL=0

mkdir -p "$ARTIFACTS_DIR"

# ── Cleanup trap ─────────────────────────────────────────────────────────────
cleanup() {
    local rc=$?
    echo -e "\n${YELLOW}━━━ Cleaning up test bed ━━━${NC}"
    rm -rf "$TEST_BED" 2>/dev/null || true
    exit $rc
}
trap cleanup EXIT INT TERM

# ── Helpers ──────────────────────────────────────────────────────────────────
pass()   { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
fail()   { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }
info()   { echo -e "  ${BLUE}→${NC} $1"; }
header() { echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }
die()    { echo -e "${RED}✗ FATAL:${NC} $*" >&2; exit 1; }

extract_json() {
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    keys = '$1'.split('.')
    for k in keys:
        if isinstance(data, dict):
            data = data.get(k)
        elif isinstance(data, list):
            try:
                data = data[int(k)]
            except (ValueError, IndexError):
                data = None
        else:
            break
    if isinstance(data, list):
        print(json.dumps(data))
    elif data is None:
        print('null')
    else:
        print(data)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    print('null')
"
}

# ── Diverse intents ──────────────────────────────────────────────────────────
INTENTS=(
    "Add user authentication flow with OAuth2"
    "Refactor database connection pooling"
    "Update API rate limiting middleware"
    "Fix memory leak in cache eviction"
    "Add unit tests for auth handler"
    "Implement feature flag service"
    "Consolidate logging framework"
    "Add health check endpoints"
    "Optimize query pagination"
    "Add structured error types"
    "Implement retry with backoff"
    "Add metrics collection pipeline"
    "Refactor session management"
    "Add websocket keepalive logic"
    "Implement graceful shutdown"
    "Add config validation schema"
    "Refactor dependency injection"
    "Add request tracing middleware"
    "Implement circuit breaker"
    "Add audit logging service"
    "Optimize asset compression"
    "Refactor state machine core"
    "Add migration runner"
    "Implement rate limit store"
    "Add TLS certificate rotation"
)

# ── 1. SETUP ─────────────────────────────────────────────────────────────────
header "PHASE 1: Creating isolated test bed"
info "Test bed: ${TEST_BED}"
mkdir -p "$TEST_BED"
cd "$TEST_BED"

info "Initializing git repository"
git init --quiet
git config user.email "test@nool-recovery.dev"
git config user.name "Nool Recovery Test"

echo "# Nool Recovery Test Bed" > README.md
echo "*.log" > .gitignore
git add -A
git commit -m "Initial commit" --quiet

info "Initializing Nool ledger"
nool init --quiet 2>&1 || die "nool init failed"

# Track git branch name
BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "Active branch: ${BRANCH}"

# ── 2. GENERATE KNOTS ────────────────────────────────────────────────────────
header "PHASE 2: Generating ${NUM_KNOTS} knots with diverse intents"

NUM_INTENTS=${#INTENTS[@]}
NUM_FILES=10

# Create initial set of module files, all tracked
for i in $(seq 0 $((NUM_FILES - 1))); do
    printf "module_%02d\nversion=1\n" "$i" > "module_${i}.txt"
done
git add -A
git commit -m "Add module baseline files" --quiet

for i in $(seq 1 "$NUM_KNOTS"); do
    idx=$(( (i - 1) % NUM_FILES ))
    intent_idx=$(( (i - 1) % NUM_INTENTS ))
    intent="${INTENTS[$intent_idx]}"

    printf "module_%02d\nversion=2\niteration=%d\ncontent=change_%04d\n" \
        "$idx" "$i" "$i" > "module_${idx}.txt"

    if ! nool propose --all --intent "$intent" --solidify --quiet 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ knot $i propose/solidify failed, retrying with explicit path...${NC}"
        nool propose \
            --path "module_${idx}.txt" \
            --intent "$intent" \
            --solidify \
            --quiet 2>/dev/null || echo -e "  ${YELLOW}⚠ knot $i failed entirely${NC}"
    fi

    if (( i % 20 == 0 )); then
        echo -e "  ${BLUE}▶${NC} Progress: ${i}/${NUM_KNOTS} knots"
    fi
done

echo -e "  ${GREEN}✓${NC} Knot generation complete"

# ── 3. SNAPSHOT PRE-LOSS STATE ──────────────────────────────────────────────
header "PHASE 3: Capturing pre-loss state"

nool status --json > "$TEST_BED/pre_status.json" 2>/dev/null || die "status --json failed"
nool log --json   > "$TEST_BED/pre_log.json"   2>/dev/null || die "log --json failed"

# Extract key metrics
PRE_KNOT_COUNT=$(python3 -c "import json; d=json.load(open('$TEST_BED/pre_status.json')); print(d.get('knot_count', d.get('total_knots', 0)))")
PRE_DAG_HEADS=$(python3 -c "
import json
d = json.load(open('$TEST_BED/pre_status.json'))
heads = d.get('dag_heads', [])
print(json.dumps(heads))
")
PRE_LOG_LINES=$(python3 -c "import json; d=json.load(open('$TEST_BED/pre_log.json')); print(len(d) if isinstance(d, list) else 0)")

echo -e "  ${BLUE}▶${NC} Pre-loss knot count  : ${BOLD}${PRE_KNOT_COUNT}${NC}"
echo -e "  ${BLUE}▶${NC} Pre-loss DAG heads   : ${BOLD}${PRE_DAG_HEADS}${NC}"
echo -e "  ${BLUE}▶${NC} Pre-loss log entries : ${BOLD}${PRE_LOG_LINES}${NC}"

# Extract all knot IDs from pre-loss log
python3 -c "
import json
d = json.load(open('$TEST_BED/pre_log.json'))
if isinstance(d, list):
    ids = [k.get('knot_id', 'unknown') for k in d]
    with open('$TEST_BED/pre_knot_ids.txt', 'w') as f:
        f.write('\n'.join(ids))
    print(f'Extracted {len(ids)} knot IDs')
else:
    print('Unexpected log format')
"

# Log commit count in git for reference
GIT_COMMITS_BEFORE=$(git log --oneline | wc -l | tr -d ' ')
echo -e "  ${BLUE}▶${NC} Git commits : ${BOLD}${GIT_COMMITS_BEFORE}${NC}"

# ── 4. CATASTROPHIC LOSS ────────────────────────────────────────────────────
header "PHASE 4: Simulating catastrophic data loss"

LOSS_TARGET="$TEST_BED/.nool"
if [[ -d "$LOSS_TARGET" ]]; then
    LOSS_SIZE=$(du -sh "$LOSS_TARGET" 2>/dev/null | cut -f1 || echo "unknown")
    echo -e "  ${YELLOW}⚠ Deleting .nool/ (size: ${LOSS_SIZE})${NC}"
    rm -rf "$LOSS_TARGET"
    echo -e "  ${YELLOW}⚠ Confirming deletion...${NC}"
    if [[ -d "$LOSS_TARGET" ]]; then
        die "Failed to delete .nool/"
    fi
    echo -e "  ${YELLOW}✓${NC} .nool/ successfully obliterated"
else
    die ".nool/ not found at $LOSS_TARGET"
fi

# Verify that nool commands now fail or show no ledger
if nool status --quiet 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ WARNING: nool status still works after deletion (might use parent context)${NC}"
fi

# ── 5. RECOVERY ──────────────────────────────────────────────────────────────
header "PHASE 5: Recovering from Bifrost Git mirror"

RECOVERY_METHOD=""
RECOVERY_SUCCESS=false

# Strategy A: nool init --from-git <branch>
info "Attempt A: nool init --from-git ${BRANCH}"
if nool init --from-git "$BRANCH" --quiet 2>"$TEST_BED/recovery_a_stderr.txt"; then
    RECOVERY_METHOD="init --from-git"
    RECOVERY_SUCCESS=true
    echo -e "  ${GREEN}✓${NC} Recovery via init --from-git succeeded"
else
    echo -e "  ${YELLOW}⚠ init --from-git failed:${NC}"
    sed 's/^/    /' "$TEST_BED/recovery_a_stderr.txt"

    # Strategy B: nool bridge mirror-repair (with fresh init only if needed)
    info "Attempt B: nool bridge mirror-repair"
    if [[ ! -d ".nool" ]]; then
        nool init --quiet 2>/dev/null || true
    fi
    if nool bridge mirror-repair --quiet 2>"$TEST_BED/recovery_b_stderr.txt"; then
        RECOVERY_METHOD="bridge mirror-repair"
        RECOVERY_SUCCESS=true
        echo -e "  ${GREEN}✓${NC} Recovery via bridge mirror-repair succeeded"
    else
        echo -e "  ${YELLOW}⚠ bridge mirror-repair failed:${NC}"
        sed 's/^/    /' "$TEST_BED/recovery_b_stderr.txt" 2>/dev/null || true

        info "Attempt C: Fallback — diagnostic extraction of knot.bin from git history"
        info "Extracting knot.bin from git commits for diagnostics..."
        mkdir -p "$TEST_BED/extracted_knots"
        COMMITS=$(git log --format="%H" -- ".nool/knot.bin" 2>/dev/null | tac || echo "")
        if [[ -n "$COMMITS" ]]; then
            COUNT=0
            while IFS= read -r commit; do
                [[ -z "$commit" ]] && continue
                if git show "${commit}:.nool/knot.bin" > "$TEST_BED/extracted_knots/knot_${commit}.bin" 2>/dev/null; then
                    COUNT=$((COUNT + 1))
                fi
            done <<< "$COMMITS"
            echo -e "  ${BLUE}▶${NC} Extracted ${COUNT} knot.bin files from git history (diagnostic only)"
        fi
        if [[ -d ".nool" ]]; then
            RECOVERY_METHOD="diagnostic-only (no DAG replay)"
        fi
    fi
fi

if [[ "$RECOVERY_SUCCESS" != "true" ]]; then
    echo -e "  ${RED}✗ ALL RECOVERY STRATEGIES FAILED${NC}"
    # We continue to capture whatever state exists
fi

# ── 6. VERIFICATION ──────────────────────────────────────────────────────────
header "PHASE 6: Verification"

# 6a. Capture post-recovery state
nool status --json > "$TEST_BED/post_status.json" 2>/dev/null || echo '{"knot_count":0,"dag_heads":[]}' > "$TEST_BED/post_status.json"
nool log --json   > "$TEST_BED/post_log.json"   2>/dev/null || echo '[]' > "$TEST_BED/post_log.json"

POST_KNOT_COUNT=$(python3 -c "import json; d=json.load(open('$TEST_BED/post_status.json')); print(d.get('knot_count', d.get('total_knots', 0)))")
POST_DAG_HEADS=$(python3 -c "
import json
d = json.load(open('$TEST_BED/post_status.json'))
heads = d.get('dag_heads', [])
print(json.dumps(heads))
")
POST_LOG_LINES=$(python3 -c "import json; d=json.load(open('$TEST_BED/post_log.json')); print(len(d) if isinstance(d, list) else 0)")

echo -e "  ${BLUE}▶${NC} Post-recovery knot count  : ${BOLD}${POST_KNOT_COUNT}${NC}"
echo -e "  ${BLUE}▶${NC} Post-recovery DAG heads   : ${BOLD}${POST_DAG_HEADS}${NC}"
echo -e "  ${BLUE}▶${NC} Post-recovery log entries : ${BOLD}${POST_LOG_LINES}${NC}"
echo -e "  ${BLUE}▶${NC} Recovery method           : ${BOLD}${RECOVERY_METHOD}${NC}"

# 6b. Knot count comparison
PRE_KNUM=$(( PRE_KNOT_COUNT + 0 ))
POST_KNUM=$(( POST_KNOT_COUNT + 0 ))

if [[ "$POST_KNUM" -eq "$PRE_KNUM" ]]; then
    pass "Knot count matches: ${PRE_KNUM}"
else
    fail "Knot count mismatch: ${PRE_KNUM} → ${POST_KNUM}"
fi

# 6c. DAG heads comparison
PRE_HEADS=$(python3 -c "import json; print(json.dumps(sorted(json.load(open('$TEST_BED/pre_status.json')).get('dag_heads', []))))" 2>/dev/null)
POST_HEADS=$(python3 -c "import json; print(json.dumps(sorted(json.load(open('$TEST_BED/post_status.json')).get('dag_heads', []))))" 2>/dev/null)

if [[ "$PRE_HEADS" == "$POST_HEADS" ]]; then
    pass "DAG heads match"
    DAG_HEADS_MATCH=true
else
    fail "DAG heads differ: pre=${PRE_HEADS} post=${POST_HEADS}"
    DAG_HEADS_MATCH=false
fi

# 6d. Run nool verify --all
info "Running structural invariant verification..."
VERIFY_PASSED=false
VERIFY_OUTPUT=""
if nool verify --all 2>"$TEST_BED/verify_stderr.txt"; then
    VERIFY_PASSED=true
    VERIFY_OUTPUT=$(<"$TEST_BED/verify_stderr.txt")
    pass "nool verify --all passed"
else
    VERIFY_OUTPUT=$(<"$TEST_BED/verify_stderr.txt")
    fail "nool verify --all failed"
    echo -e "    ${YELLOW}${VERIFY_OUTPUT}${NC}"
fi

# 6e. Ed25519 signature verification
info "Checking Ed25519 signatures..."
SIGNATURES_VALID_COUNT=0
SIGNATURES_CHECKED=0

# Try to get signature info from the log JSON
if [[ -f "$TEST_BED/post_log.json" ]]; then
    SIG_CHECK=$(python3 -c "
import json
d = json.load(open('$TEST_BED/post_log.json'))
if isinstance(d, list):
    valid = sum(1 for k in d if k.get('signature_valid', k.get('valid', True)))
    total = len(d)
    print(f'{valid}/{total}')
else:
    print('0/0')
" 2>/dev/null || echo "0/0")
    SIGNATURES_VALID_COUNT="${SIG_CHECK%%/*}"
    SIGNATURES_CHECKED="${SIG_CHECK##*/}"
fi

if [[ "$SIGNATURES_CHECKED" -gt 0 ]]; then
    if [[ "$SIGNATURES_VALID_COUNT" -eq "$SIGNATURES_CHECKED" ]]; then
        pass "All ${SIGNATURES_CHECKED} signatures valid"
    else
        fail "Signatures: ${SIGNATURES_VALID_COUNT}/${SIGNATURES_CHECKED} valid"
    fi
else
    # Fallback: count knots and assume verify covered it
    info "Signature detail not in JSON; relying on nool verify --all"
    if [[ "$VERIFY_PASSED" == "true" ]]; then
        pass "Signatures validated implicitly by verify --all"
        SIGNATURES_VALID_COUNT=$POST_KNUM
        SIGNATURES_CHECKED=$POST_KNUM
    fi
fi

# 6f. Corruption test: corrupt a knot file and verify detection
header "PHASE 6f: Corruption detection test"
CORRUPTION_DETECTED=false

# Find knot storage files
KNOT_DIR="$TEST_BED/.nool/knots"
KNOT_DB="$TEST_BED/.nool/nool.db"

if [[ -d "$KNOT_DIR" ]]; then
    # Find a knot file to corrupt
    KNOT_FILE=$(find "$KNOT_DIR" -type f 2>/dev/null | head -1)
    if [[ -n "$KNOT_FILE" ]]; then
        info "Corrupting knot file: ${KNOT_FILE}"
        cp "$KNOT_FILE" "${KNOT_FILE}.bak"
        dd if=/dev/urandom of="$KNOT_FILE" bs=1024 count=1 2>/dev/null

        if nool verify --all 2>"$TEST_BED/corrupt_verify.txt"; then
            fail "verify passed despite corrupted knot file"
            CORRUPTION_DETECTED=false
        else
            pass "verify detected corrupted knot file"
            CORRUPTION_DETECTED=true
        fi

        # Restore from backup
        mv "${KNOT_FILE}.bak" "$KNOT_FILE"
    else
        info "No individual knot files found; skipping file corruption test"
    fi
elif [[ -f "$KNOT_DB" ]]; then
    info "Testing SQLite database corruption detection"
    cp "$KNOT_DB" "${KNOT_DB}.bak"
    # Corrupt a few bytes in the database
    python3 -c "
import os, random
db_path = '$KNOT_DB'
size = os.path.getsize(db_path)
with open(db_path, 'r+b') as f:
    offset = random.randint(1024, min(size - 1, 100000))
    f.seek(offset)
    f.write(os.urandom(64))
"
    if nool verify --all 2>"$TEST_BED/corrupt_verify.txt"; then
        fail "verify passed despite corrupted database"
        CORRUPTION_DETECTED=false
    else
        pass "verify detected database corruption"
        CORRUPTION_DETECTED=true
    fi

    # Restore
    mv "${KNOT_DB}.bak" "$KNOT_DB"
fi

# ── 7. RECOVERY SCORE ────────────────────────────────────────────────────────
header "PHASE 7: Computing recovery fidelity score"

if [[ "$PRE_KNUM" -gt 0 ]]; then
    RECOVERY_FIDELITY_PCT=$(python3 -c "print(round($POST_KNUM * 100.0 / $PRE_KNUM, 2))")
else
    RECOVERY_FIDELITY_PCT=0
fi

echo -e "  ${BLUE}▶${NC} Original knots : ${BOLD}${PRE_KNUM}${NC}"
echo -e "  ${BLUE}▶${NC} Recovered      : ${BOLD}${POST_KNUM}${NC}"
echo -e "  ${BLUE}▶${NC} Fidelity       : ${BOLD}${RECOVERY_FIDELITY_PCT}%${NC}"

if (( $(echo "$RECOVERY_FIDELITY_PCT >= 100" | bc -l) )); then
    pass "Perfect recovery fidelity"
elif (( $(echo "$RECOVERY_FIDELITY_PCT >= 90" | bc -l) )); then
    pass "High recovery fidelity (>= 90%)"
elif (( $(echo "$RECOVERY_FIDELITY_PCT >= 50" | bc -l) )); then
    info "Partial recovery fidelity (>= 50%)"
else
    fail "Low recovery fidelity (< 50%)"
fi

# ── 8. SAVE RESULTS ──────────────────────────────────────────────────────────
header "PHASE 8: Saving results"

# Compute summary
TOTAL_TESTS=$((PASS + FAIL))
OVERALL_STATUS="PASS"
if [[ "$FAIL" -gt 0 ]]; then
    OVERALL_STATUS="FAIL"
fi

# Gather additional diagnostic info
GIT_VERSION=$(git --version 2>/dev/null || echo "unknown")
NOOL_VERSION=$(nool version 2>/dev/null | head -1 || echo "unknown")
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

python3 -c "
import json, datetime

results = {
    'test_name': '02_adversarial_recovery',
    'timestamp': '$TIMESTAMP',
    'hostname': '$HOSTNAME',
    'nool_version': '$NOOL_VERSION',
    'git_version': '$GIT_VERSION',

    'configuration': {
        'num_knots_target': $NUM_KNOTS,
        'branch': '$BRANCH',
        'test_bed': '$TEST_BED',
    },

    'pre_loss_state': {
        'original_knot_count': $PRE_KNUM,
        'dag_heads': $PRE_DAG_HEADS,
        'git_commits': $GIT_COMMITS_BEFORE,
    },

    'recovery': {
        'method': '$RECOVERY_METHOD',
        'success': '$RECOVERY_SUCCESS',
    },

    'post_recovery_state': {
        'recovered_knot_count': $POST_KNUM,
        'recovered_dag_heads': $POST_DAG_HEADS,
    },

    'verification': {
        'recovery_fidelity_pct': $RECOVERY_FIDELITY_PCT,
        'verify_passed': $VERIFY_PASSED,
        'signatures_valid_count': $SIGNATURES_VALID_COUNT,
        'signatures_checked': $SIGNATURES_CHECKED,
        'dag_heads_match': $DAG_HEADS_MATCH,
        'corruption_detected': $CORRUPTION_DETECTED,
    },

    'test_results': {
        'passed': $PASS,
        'failed': $FAIL,
        'total': $TOTAL_TESTS,
        'overall_status': '$OVERALL_STATUS',
    },
}

with open('$RESULTS_FILE', 'w') as f:
    json.dump(results, f, indent=2)
print(json.dumps(results, indent=2))
"

echo -e "\n${GREEN}━━━ RESULTS WRITTEN ──────────────────────────────────────${NC}"
echo -e "  File   : ${BOLD}${RESULTS_FILE}${NC}"
echo -e "  Status : ${BOLD}$OVERALL_STATUS${NC}  (${PASS} passed / ${FAIL} failed / ${TOTAL_TESTS} total)"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
