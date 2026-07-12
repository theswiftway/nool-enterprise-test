#!/bin/bash
set -euo pipefail

NOOL="/usr/local/bin/nool"
SCENARIO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCENARIO_DIR"

SECONDS=0
echo "============================================================"
echo " SCENARIO 02: Governance Policy Enforcement Stress"
echo " Started:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"

# ── Phase 1: Show governance config ─────────────────────────────
echo ""
echo "[PHASE 1] Displaying current configuration"
$NOOL config show --compact 2>&1 || echo "[WARN] config show had non-zero exit"

# ── Phase 2: Define consortium in governance/ ────────────────────
echo ""
echo "[PHASE 2] Creating consortium governance definition"

mkdir -p governance

cat > governance/consortium.toml << 'GOVEOF'
[consortium.enterprise-review]
quorum = 3
veto = 2
members = [
  { role = "architect",  model = "host" },
  { role = "ciso",       model = "host" },
  { role = "tech-lead",  model = "host" },
]
review_threshold = "majority"
GOVEOF
echo "  [✓] Created governance/consortium.toml"

# ── Phase 3: Security-sensitive changes ──────────────────────────
echo ""
echo "[PHASE 3] Creating changes across security-sensitive paths"

mkdir -p tmp/governance
echo "secret=encrypted_value" > tmp/governance/.env.production
echo 'password_hashing = "bcrypt"' > tmp/governance/auth_config.toml
echo 'tls_cert_path = "/etc/certs/prod.pem"' > tmp/governance/tls_config.toml

$NOOL propose \
  --path tmp/governance/.env.production \
  --intent "update production secrets" \
  --thread governance-stress \
  --fast 2>&1 || echo "[WARN] propose (env) had non-zero exit"

$NOOL propose \
  --path tmp/governance/auth_config.toml \
  --intent "update auth security config" \
  --thread governance-stress \
  --fast 2>&1 || echo "[WARN] propose (auth config) had non-zero exit"

$NOOL propose \
  --path tmp/governance/tls_config.toml \
  --intent "update TLS certificate path" \
  --thread governance-stress \
  --fast 2>&1 || echo "[WARN] propose (tls) had non-zero exit"

$NOOL propose \
  --path governance/consortium.toml \
  --intent "define enterprise consortium" \
  --thread governance-stress \
  --fast 2>&1 || echo "[WARN] propose (consortium) had non-zero exit"

# ── Phase 4: Test steering gates ─────────────────────────────────
echo ""
echo "[PHASE 4] Testing steering gates"

# Get first knot ID + intent for steering
STEER_DATA=$($NOOL log --json --limit 10 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.loads(sys.stdin.read())
    if isinstance(data, list) and data:
        first = data[0]
        kid = first.get('id', '')
        summary = first.get('summary', '') or ''
        intent = ''
        for line in summary.split('\n'):
            if line.startswith('Intent:'):
                intent = line.split('Intent:', 1)[1].strip()
                break
        print(f'{kid}|{intent}')
except: pass
" 2>/dev/null || echo "")

if [ -n "$STEER_DATA" ]; then
  FIRST_KNOT="${STEER_DATA%%|*}"
  KNOT_INTENT="${STEER_DATA#*|}"
  echo "  Steering target: $FIRST_KNOT"
  echo "  Knot intent: ${KNOT_INTENT:-"(none)"}"

  if [ -z "$KNOT_INTENT" ] || [ "$KNOT_INTENT" = "null" ]; then
    CHALLENGE_ANSWER="2"
  else
    CHALLENGE_ANSWER="1"
  fi

  printf "$CHALLENGE_ANSWER\n" | $NOOL steer \
    --point pre-solidify \
    --role architect \
    --action approve \
    --target "$FIRST_KNOT" \
    --value "Architecture review: approved" \
    --compact 2>&1 || echo "[WARN] steer (architect approve) had non-zero exit"

  printf "$CHALLENGE_ANSWER\n" | $NOOL steer \
    --point pre-push \
    --role ciso \
    --action approve \
    --target "$FIRST_KNOT" \
    --value "CISO security review: approved" \
    --compact 2>&1 || echo "[WARN] steer (ciso approve) had non-zero exit"
else
  echo "  [SKIP] No knot available for steering (may need to solidify first)"
fi

# ── Phase 5: Run invariant verification ───────────────────────────
echo ""
echo "[PHASE 5] Running structural invariant verification"
$NOOL verify --all --compact 2>&1 || echo "[WARN] verify had non-zero exit"

# ── Phase 6: Compliance audit ────────────────────────────────────
echo ""
echo "[PHASE 6] Producing compliance audit report"
$NOOL audit report --compact 2>&1 || echo "[WARN] audit report had non-zero exit"

$NOOL audit steering --compact 2>&1 || echo "[WARN] audit steering had non-zero exit"

# ── Phase 7: Solidify governance thread ──────────────────────────
echo ""
echo "[PHASE 7] Solidifying governance proposals"
$NOOL solidify --thread governance-stress --fast 2>&1 || echo "[WARN] solidify had non-zero exit; may be queue ordering"

# ── Duration ─────────────────────────────────────────────────────
DURATION=$SECONDS
echo ""
echo "============================================================"
echo " SCENARIO 02 COMPLETE — duration: ${DURATION}s"
echo "============================================================"
