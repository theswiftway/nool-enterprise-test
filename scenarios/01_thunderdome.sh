#!/bin/bash
set -euo pipefail

NOOL="/usr/local/bin/nool"
SCENARIO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCENARIO_DIR"

SECONDS=0
echo "============================================================"
echo " SCENARIO 01: Multi-Agent Conflict Gauntlet"
echo " Started:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"

# ── Phase 1: Pre-flight ──────────────────────────────────────────
echo ""
echo "[PHASE 1] Pre-flight — gathering status and features"
$NOOL status --compact 2>&1 || echo "[WARN] status command had non-zero exit"
$NOOL discover features --compact 2>&1 || true

# ── Phase 2: Announce 3 intents ──────────────────────────────────
echo ""
echo "[PHASE 2] Announcing 3 simulated agent intents"
ANNOUNCE1=$($NOOL announce intent \
  --intent "agent-alpha: implement rate limiter" \
  --target-nodes "src/rate_limiter" \
  --estimated-duration-ms 120000 \
  --thread thunderdome 2>&1) && echo "$ANNOUNCE1" || echo "[WARN] $ANNOUNCE1"

ANNOUNCE2=$($NOOL announce intent \
  --intent "agent-beta: add auth middleware" \
  --target-nodes "src/auth" \
  --estimated-duration-ms 90000 \
  --thread thunderdome 2>&1) && echo "$ANNOUNCE2" || echo "[WARN] $ANNOUNCE2"

ANNOUNCE3=$($NOOL announce intent \
  --intent "agent-gamma: refactor database layer" \
  --target-nodes "src/db" \
  --estimated-duration-ms 150000 \
  --thread thunderdome 2>&1) && echo "$ANNOUNCE3" || echo "[WARN] $ANNOUNCE3"

# ── Phase 3: Parallel work ───────────────────────────────────────
echo ""
echo "[PHASE 3] Starting parallel work"
$NOOL work start \
  --intent "thunderdome-gauntlet" \
  --parallel 3 \
  --compact 2>&1 || echo "[WARN] work start had non-zero exit"

# ── Phase 4: Conflict detection ──────────────────────────────────
echo ""
echo "[PHASE 4] Detecting conflicts across announcements"
$NOOL discover conflicts --compact 2>&1 || echo "[WARN] discover conflicts had non-zero exit"

# ── Phase 5: Create changes and propose ──────────────────────────
echo ""
echo "[PHASE 5] Creating isolated changes and proposing"

mkdir -p tmp/thunderdome

echo "// Rate limiter stub" > tmp/thunderdome/rate_limiter.rs
echo "// Auth middleware stub" > tmp/thunderdome/auth_middleware.rs
echo "// DB layer stub" > tmp/thunderdome/db_layer.rs

$NOOL propose \
  --path tmp/thunderdome/rate_limiter.rs \
  --intent "agent-alpha: implement rate limiter" \
  --thread thunderdome \
  --fast 2>&1 || echo "[WARN] propose (rate limiter) had non-zero exit"

$NOOL propose \
  --path tmp/thunderdome/auth_middleware.rs \
  --intent "agent-beta: add auth middleware" \
  --thread thunderdome \
  --fast 2>&1 || echo "[WARN] propose (auth middleware) had non-zero exit"

$NOOL propose \
  --path tmp/thunderdome/db_layer.rs \
  --intent "agent-gamma: refactor database layer" \
  --thread thunderdome \
  --fast 2>&1 || echo "[WARN] propose (db layer) had non-zero exit"

# ── Phase 6: Solidify ────────────────────────────────────────────
echo ""
echo "[PHASE 6] Solidifying proposals"
$NOOL solidify --thread thunderdome --fast 2>&1 || echo "[WARN] solidify had non-zero exit; may be queue ordering"

# ── Phase 7: Verify and inspect ──────────────────────────────────
echo ""
echo "[PHASE 7] Verification and DAG inspection"
$NOOL verify --all --compact 2>&1 || echo "[WARN] verify had non-zero exit"
$NOOL log --compact --thread thunderdome 2>&1 || echo "[WARN] log had non-zero exit"

# ── Duration ─────────────────────────────────────────────────────
DURATION=$SECONDS
echo ""
echo "============================================================"
echo " SCENARIO 01 COMPLETE — duration: ${DURATION}s"
echo "============================================================"
