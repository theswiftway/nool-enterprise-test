#!/bin/bash
set -euo pipefail

NOOL="/usr/local/bin/nool"
SCENARIO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCENARIO_DIR"

SECONDS=0
echo "============================================================"
echo " SCENARIO 03: Fleet Coordination Operation"
echo " Started:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"

# ── Phase 1: Create agent specs ──────────────────────────────────
echo ""
echo "[PHASE 1] Creating agent specification files"

mkdir -p agents

cat > agents/builder.yaml << 'YAMLEOF'
name: builder-alpha
executor: host
model: host
max_tokens: 4096
temperature: 0.3
YAMLEOF
echo "  [✓] Created agents/builder.yaml"

cat > agents/reviewer.yaml << 'YAMLEOF'
name: reviewer-gamma
executor: host
model: host
max_tokens: 2048
temperature: 0.2
YAMLEOF
echo "  [✓] Created agents/reviewer.yaml"

# ── Phase 2: Validate agent specs ────────────────────────────────
echo ""
echo "[PHASE 2] Validating agent specs"
$NOOL agent list --compact 2>&1 || echo "[WARN] agent list had non-zero exit"

# ── Phase 3: Fleet plan ──────────────────────────────────────────
echo ""
echo "[PHASE 3] Creating disjoint fleet plan"
$NOOL fleet plan \
  --task "rate-limiter=tmp/thunderdome/rate_limiter.rs" \
  --task "auth-middleware=tmp/thunderdome/auth_middleware.rs" \
  --compact 2>&1 || echo "[WARN] fleet plan had non-zero exit"

# ── Phase 4: Create work for fleet tasks ─────────────────────────
echo ""
echo "[PHASE 4] Creating fleet work items"

mkdir -p tmp/fleet

echo "def rate_limit(): pass" > tmp/fleet/rate_limiter.py
echo "def authenticate(): pass" > tmp/fleet/auth_middleware.py
echo "def query_db(): pass" > tmp/fleet/db_query.py

$NOOL propose \
  --path tmp/fleet/rate_limiter.py \
  --intent "fleet: implement rate limiter in Python" \
  --thread fleet-ops \
  --fast 2>&1 || echo "[WARN] propose (rate_limiter) had non-zero exit"

$NOOL propose \
  --path tmp/fleet/auth_middleware.py \
  --intent "fleet: add auth middleware in Python" \
  --thread fleet-ops \
  --fast 2>&1 || echo "[WARN] propose (auth_middleware) had non-zero exit"

$NOOL propose \
  --path tmp/fleet/db_query.py \
  --intent "fleet: add database query module" \
  --thread fleet-ops \
  --fast 2>&1 || echo "[WARN] propose (db_query) had non-zero exit"

# ── Phase 5: Simulate council review ─────────────────────────────
echo ""
echo "[PHASE 5] Running council review"

mkdir -p tmp
git diff HEAD -- tmp/fleet/ 2>/dev/null > tmp/fleet_diff.patch || true
echo "  [INFO] Council requires consortium config in nool.toml"
echo "  [SKIP] Council requires --consortium from nool.toml [consortium.*] section"
echo "  [INFO] To run council manually: nool council --consortium <name>"

# ── Phase 6: Solidify fleet thread ───────────────────────────────
echo ""
echo "[PHASE 6] Solidifying fleet proposals"
$NOOL solidify --thread fleet-ops --fast 2>&1 || echo "[WARN] solidify had non-zero exit; may be queue ordering"

# ── Phase 7: Status check ────────────────────────────────────────
echo ""
echo "[PHASE 7] Final state check"
$NOOL status --compact 2>&1 || echo "[WARN] status had non-zero exit"

# ── Duration ─────────────────────────────────────────────────────
DURATION=$SECONDS
echo ""
echo "============================================================"
echo " SCENARIO 03 COMPLETE — duration: ${DURATION}s"
echo "============================================================"
