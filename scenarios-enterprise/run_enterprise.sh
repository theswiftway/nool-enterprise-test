#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="/tmp/nool-enterprise-test"
ARTIFACTS_DIR="${BASE_DIR}/artifacts-enterprise"
SCENARIOS=(
  "01_load_generation.sh:Load Generation — 100K DAG"
  "02_adversarial_recovery.sh:Adversarial Recovery — Data Loss + Bifrost Restoration"
  "03_convergence_torture.sh:Convergence Torture — N Agent Race"
  "04_signature_audit.sh:Signature Chain Audit — Ed25519 Integrity"
  "05_long_running_stability.sh:Long-Running Stability — 24h Simulated"
)

mkdir -p "$ARTIFACTS_DIR"

echo "============================================================"
echo " NOOL ENTERPRISE VALIDATION SUITE"
echo " $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
echo "============================================================"
echo ""

for entry in "${SCENARIOS[@]}"; do
  script="${entry%%:*}"
  label="${entry##*:}"
  path="${BASE_DIR}/scenarios-enterprise/${script}"

  if [ ! -f "$path" ]; then
    echo "  [SKIP] $label — script not found at $path"
    continue
  fi

  echo "────────────────────────────────────────────────────────"
  echo " RUNNING: $label"
  echo "────────────────────────────────────────────────────────"

  start=$(date +%s)
  set +e
  bash "$path"
  rc=$?
  set -e
  end=$(date +%s)

  if [ $rc -eq 0 ]; then
    echo "  [PASS] $label ($((end - start))s)"
  else
    echo "  [FAIL] $label exited $rc ($((end - start))s)"
  fi
  echo ""
done

echo "============================================================"
echo " SUITE COMPLETE — results in $ARTIFACTS_DIR"
echo "============================================================"
