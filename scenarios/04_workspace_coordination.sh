#!/bin/bash
set -euo pipefail

NOOL="/usr/local/bin/nool"
SCENARIO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCENARIO_DIR"

SECONDS=0
echo "============================================================"
echo " SCENARIO 04: Polyglot Workspace Coordination"
echo " Started:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"

# ── Phase 1: Show workspace tree ─────────────────────────────────
echo ""
echo "[PHASE 1] Workspace tree status"
$NOOL workspace status --compact 2>&1 || echo "[WARN] workspace status had non-zero exit"

$NOOL workspace status --json --compact 2>&1 || echo "[WARN] workspace json had non-zero exit"

# ── Phase 2: Decompose goals into child projects ─────────────────
echo ""
echo "[PHASE 2] Decomposing workspace goals"
$NOOL workspace goal \
  --intent "analytics-dashboard-sprint" \
  --decompose analytics="build-usage-dashboard" \
  --save --compact 2>&1 || echo "[WARN] goal decompose (analytics) had non-zero exit"

$NOOL workspace goal \
  --intent "auth-upgrade-sprint" \
  --decompose auth-gateway="upgrade-oauth-provider" \
  --save --compact 2>&1 || echo "[WARN] goal decompose (auth-gateway) had non-zero exit"

$NOOL workspace goal \
  --intent "core-refactor-sprint" \
  --decompose core-service="refactor-api-handler" \
  --save --compact 2>&1 || echo "[WARN] goal decompose (core-service) had non-zero exit"

# ── Phase 3: Create Knots in child projects ──────────────────────
echo ""
echo "[PHASE 3] Creating changes in child projects"

mkdir -p workspace/analytics/dashboards
echo "SELECT * FROM usage_metrics" > workspace/analytics/dashboards/usage.sql
$NOOL propose \
  --path workspace/analytics/dashboards/usage.sql \
  --intent "analytics: add usage dashboard query" \
  --thread workspace-analytics \
  --fast 2>&1 || echo "[WARN] propose (analytics) had non-zero exit"

mkdir -p workspace/auth-gateway/config
echo "oauth_provider = 'OIDC'" > workspace/auth-gateway/config/oauth.toml
$NOOL propose \
  --path workspace/auth-gateway/config/oauth.toml \
  --intent "auth-gateway: configure OIDC provider" \
  --thread workspace-auth \
  --fast 2>&1 || echo "[WARN] propose (auth-gateway) had non-zero exit"

mkdir -p workspace/core-service/src
echo "fn handle_request() -> &'static str { \"ok\" }" > workspace/core-service/src/handler.rs
$NOOL propose \
  --path workspace/core-service/src/handler.rs \
  --intent "core-service: refactor API handler" \
  --thread workspace-core \
  --fast 2>&1 || echo "[WARN] propose (core-service) had non-zero exit" || true

mkdir -p workspace/identity/config
echo "identity_provider = 'keycloak'" > workspace/identity/config/provider.toml
$NOOL propose \
  --path workspace/identity/config/provider.toml \
  --intent "identity: configure Keycloak provider" \
  --thread workspace-identity \
  --fast 2>&1 || echo "[WARN] propose (identity) had non-zero exit"

# ── Phase 4: Solidify child project proposals ────────────────────
echo ""
echo "[PHASE 4] Solidifying child project proposals"

$NOOL solidify --thread workspace-analytics --fast 2>&1 || echo "[WARN] solidify (analytics) had non-zero exit"
$NOOL solidify --thread workspace-auth --fast 2>&1 || echo "[WARN] solidify (auth) had non-zero exit"
$NOOL solidify --thread workspace-core --fast 2>&1 || echo "[WARN] solidify (core) had non-zero exit"
$NOOL solidify --thread workspace-identity --fast 2>&1 || echo "[WARN] solidify (identity) had non-zero exit"

# ── Phase 5: Workspace pull to aggregate ─────────────────────────
echo ""
echo "[PHASE 5] Aggregating via workspace pull"
$NOOL workspace pull --compact 2>&1 || echo "[WARN] workspace pull had non-zero exit (expected: no remote)"

# ── Phase 6: Verify final workspace state ────────────────────────
echo ""
echo "[PHASE 6] Final workspace state"
$NOOL workspace status --compact 2>&1 || echo "[WARN] final workspace status had non-zero exit"

# ── Duration ─────────────────────────────────────────────────────
DURATION=$SECONDS
echo ""
echo "============================================================"
echo " SCENARIO 04 COMPLETE — duration: ${DURATION}s"
echo "============================================================"
