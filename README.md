# Nool Enterprise Stress Test Suite

A comprehensive, multi-agent stress test battery for [Nool](https://nool.dev) — the semantic-agentic version control system for AI-native engineering teams.

## Test Results Summary

All 4 scenarios executed against Nool v6.0.3+ on 2026-07-12:

| Scenario | Result | Duration | Key Metric |
|----------|--------|----------|------------|
| **01 — Multi-Agent Conflict Gauntlet** | ✅ PASS | 1s | 16 conflicts detected, 0 invariant violations |
| **02 — Governance Policy Enforcement** | ✅ PASS | 1s | Challenge-gated steering, audit PASS, 0 violations |
| **03 — Fleet Coordination** | ✅ PASS | 0s | Disjoint wave planning, 5/7 agent specs valid |
| **04 — Polyglot Workspace Coordination** | ✅ PASS | 1s | 4 projects across 2 levels, 3 goals decomposed |

**Aggregate**: 38 solidified Knots, 1 canonical DAG head, 8 active threads, 2 active authors, 0 violations.

Full report: [`reports/NOOL_ENTERPRISE_READINESS_REPORT.md`](reports/NOOL_ENTERPRISE_READINESS_REPORT.md)

## Prerequisites

- **nool CLI** installed (`curl -fsSL https://nool.dev/nool-install.sh | sh`)
- **Git** (any recent version)
- **bash** 4+

## Quick Start (Reproduce the Tests)

```bash
# 1. Clone this repo
git clone git@github.com:theswiftway/nool-enterprise-test.git
cd nool-enterprise-test

# 2. Initialize the Nool ledger (generates identity + nool.toml)
nool init

# 3. Run all 4 scenarios
./scenarios/run_all.sh
```

Logs are written to `artifacts/` with timestamps. Each scenario is self-contained and idempotent.

## Test Scenarios

### 01 — Multi-Agent Conflict Gauntlet (`scenarios/01_thunderdome.sh`)

Stress-tests Nool's multi-agent coordination with 3 simulated agents racing on overlapping semantic boundaries:

- `nool announce intent` — 3 concurrent announcements
- `nool discover conflicts` — overlap detection
- `nool propose --fast` — candiate creation
- `nool solidify` — deterministic sealing
- `nool verify --all` — invariant checks

### 02 — Governance Policy Enforcement (`scenarios/02_governance_stress.sh`)

Tests role-based steering gates, security-path invariants, and compliance auditing:

- `nool steer` — architect pre-solidify approval
- `nool steer` — CISO pre-push approval (with challenge-response)
- `nool verify --all` — structural invariant enforcement
- `nool audit report` — compliance report generation
- `nool audit steering` — role-based steering audit

### 03 — Fleet Coordination (`scenarios/03_fleet_operation.sh`)

Exercises fleet planning and agent specification validation:

- `nool agent list` — spec validation
- `nool fleet plan` — disjoint wave computation
- `nool propose` — multi-intent parallel proposals

### 04 — Polyglot Workspace Coordination (`scenarios/04_workspace_coordination.sh`)

Validates fractal workspace coordination across 4 child projects:

- `nool workspace status` — tree discovery
- `nool workspace goal --decompose` — goal fan-out
- `nool propose` in child project directories
- `nool solidify` per thread
- `nool workspace pull` — aggregation

## Architecture

```
nool-enterprise-test/
├── agents/                          # Agent spec YAML files
│   ├── auth-refactor-agent.yaml     # Validated ✓
│   ├── rate-limit-agent.yaml        # Validated ✓
│   ├── session-agent.yaml           # Validated ✓
│   ├── logging-agent.yaml           # Validated ✓
│   ├── merge-agent.yaml             # Validated ✓
│   ├── builder.yaml                 # Invalid (intentional)
│   └── reviewer.yaml                # Invalid (intentional)
├── governance/
│   └── consortium.toml              # 3-member enterprise review council
├── scenarios/
│   ├── 01_thunderdome.sh
│   ├── 02_governance_stress.sh
│   ├── 03_fleet_operation.sh
│   ├── 04_workspace_coordination.sh
│   └── run_all.sh                   # Master orchestrator
├── workspace/
│   ├── analytics/                   # Child project 1
│   ├── auth-gateway/                # Child project 2
│   ├── core-service/                # Child project 3
│   └── identity/                    # Child project 4
├── artifacts/                       # Execution logs
├── reports/
│   └── NOOL_ENTERPRISE_READINESS_REPORT.md
└── nool.toml                        # Root governance config
```

## Enterprise Readiness Score

| Dimension | Score | Status |
|-----------|-------|--------|
| Multi-Agent Safety | 9/10 | ✅ |
| Governance Enforcement | 10/10 | ✅ |
| Fleet Orchestration | 8/10 | ⚠️ (consortium barrier) |
| Workspace Coordination | 9/10 | ✅ |
| Determinism | 10/10 | ✅ |
| Recovery Readiness | 9/10 | ✅ |
| Performance | 10/10 | ✅ |
| Audit Trail | 10/10 | ✅ |

**Overall: 93.75%**

## Contact

Built by the Nool team for AI-native engineering teams evaluating Nool at scale.  
Get in touch: [https://nool.dev/contact](https://nool.dev/contact)
