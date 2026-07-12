#!/bin/bash
set -euo pipefail

NOOL="/usr/local/bin/nool"
SCENARIO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS_DIR="$SCENARIO_DIR/artifacts"
TIMESTAMP=$(date -u +'%Y%m%d_%H%M%S')
SUMMARY_LOG="$ARTIFACTS_DIR/run_summary_$TIMESTAMP.log"

cd "$SCENARIO_DIR"

mkdir -p "$ARTIFACTS_DIR"

echo "============================================================"
echo " NOOL ENTERPRISE TEST SUITE"
echo " Started:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo " Workspace:  $SCENARIO_DIR"
echo " Artifacts:  $ARTIFACTS_DIR"
echo "============================================================"
echo ""

# Pre-flight check
echo "[PRE-FLIGHT] Verifying Nool CLI availability..."
if ! command -v "$NOOL" &>/dev/null; then
  echo "  [FAIL] nool CLI not found at $NOOL"
  exit 1
fi
echo "  [PASS] nool CLI found: $($NOOL --help 2>&1 | head -1 || true)"

echo "[PRE-FLIGHT] Checking workspace status..."
$NOOL status --compact 2>&1 || echo "  [WARN] status check had non-zero exit"
echo ""

# ── Test scenarios ───────────────────────────────────────────────
SCENARIOS=(
  "01_thunderdome.sh:Multi-Agent Conflict Gauntlet"
  "02_governance_stress.sh:Governance Policy Enforcement"
  "03_fleet_operation.sh:Fleet Coordination"
  "04_workspace_coordination.sh:Polyglot Workspace Coordination"
)

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

for entry in "${SCENARIOS[@]}"; do
  SCRIPT="${entry%%:*}"
  LABEL="${entry##*:}"
  SCRIPT_PATH="$SCENARIO_DIR/scenarios/$SCRIPT"
  LOG_FILE="$ARTIFACTS_DIR/${SCRIPT%.sh}_$TIMESTAMP.log"

  echo "────────────────────────────────────────────────────────"
  echo " RUNNING: $LABEL ($SCRIPT)"
  echo "────────────────────────────────────────────────────────"

  if [ ! -f "$SCRIPT_PATH" ]; then
    echo "  [SKIP] Script not found: $SCRIPT_PATH"
    RESULTS+=("$LABEL|SKIP|0|Script not found")
    continue
  fi

  START_TS=$(date -u +'%s')
  set +e
  bash "$SCRIPT_PATH" > "$LOG_FILE" 2>&1
  EXIT_CODE=$?
  set -e
  END_TS=$(date -u +'%s')
  DURATION=$((END_TS - START_TS))

  if [ $EXIT_CODE -eq 0 ]; then
    echo "  [PASS] $LABEL completed in ${DURATION}s"
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("$LABEL|PASS|${DURATION}s|")
  else
    echo "  [FAIL] $LABEL exited with code $EXIT_CODE after ${DURATION}s"
    echo "  [INFO] Tail of log:"
    tail -5 "$LOG_FILE" 2>/dev/null | sed 's/^/         /'
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("$LABEL|FAIL|${DURATION}s|exit=$EXIT_CODE")
  fi
  echo ""
done

# ── Summary ──────────────────────────────────────────────────────
echo "============================================================"
echo " TEST SUITE SUMMARY"
echo "============================================================"
echo ""

for result in "${RESULTS[@]}"; do
  IFS='|' read -r name status duration detail <<< "$result"
  if [ "$status" = "PASS" ]; then
    printf "  [PASS] %-45s %s\n" "$name" "$duration"
  elif [ "$status" = "SKIP" ]; then
    printf "  [SKIP] %-45s %s\n" "$name" "$detail"
  else
    printf "  [FAIL] %-45s %s (%s)\n" "$name" "$duration" "$detail"
  fi
done | tee -a "$SUMMARY_LOG"

echo ""
echo "  Passed: $PASS_COUNT / $((PASS_COUNT + FAIL_COUNT))"
echo "  Failed: $FAIL_COUNT"
echo "  Completed: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "  ✓ ALL SCENARIOS PASSED"
  exit 0
else
  echo "  ✗ $FAIL_COUNT SCENARIO(S) FAILED (see logs in $ARTIFACTS_DIR)"
  exit 1
fi
echo "============================================================"
