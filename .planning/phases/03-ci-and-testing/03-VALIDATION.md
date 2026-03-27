---
phase: 3
slug: ci-and-testing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | YAML inspection + `gh` CLI + GitHub Actions (CI run) |
| **Config file** | `.github/workflows/ci.yml`, `.github/workflows/update-types.yml` |
| **Quick run command** | `grep -q 'spiceflare-codegen' .github/workflows/ci.yml && grep -q '5.4.x' .github/workflows/ci.yml && echo "OK"` |
| **Full suite command** | `grep -q 'spiceflare-codegen' .github/workflows/update-types.yml && grep -q 'spiceflare-codegen' .github/workflows/ci.yml && grep -q '5.4.x' .github/workflows/ci.yml && grep -q 'matrix' .github/workflows/ci.yml && grep -q 'melange-check' .github/workflows/ci.yml && echo "ALL WORKFLOW CHECKS PASSED"` |
| **Estimated runtime** | ~5 seconds (local grep) |

---

## Sampling Rate

- **After every task commit:** Run quick run command above
- **After every plan wave:** Run full suite command above
- **Before `/gsd:verify-work`:** Full suite must be green + CI run must pass on GitHub
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | TEST-02 | grep | `grep -q 'matrix' .github/workflows/ci.yml && grep -q '5.4.x' .github/workflows/ci.yml && grep -q 'melange-check' .github/workflows/ci.yml && echo "OK"` | ✅ | ⬜ pending |
| 3-01-02 | 01 | 1 | REL-02 | grep | `grep -q 'spiceflare-codegen' .github/workflows/update-types.yml && grep -q '5.4.x' .github/workflows/update-types.yml && echo "OK"` | ✅ | ⬜ pending |
| 3-01-03 | 01 | 1 | TEST-02 | manual | Push branch, verify 3 jobs pass in GitHub Actions UI (build(spiceflare), build(spiceflare-codegen), melange-check) | N/A | ⬜ pending |
| 3-01-04 | 01 | 1 | TEST-02 | gh | `gh api /repos/{owner}/{repo}/branches/main/protection --jq '.required_status_checks.checks[].context'` | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No framework installation needed — this phase modifies YAML workflow files and runs `gh api`. All automated checks are grep-based.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| CI workflows pass on GitHub Actions | TEST-02 | Requires a push to trigger actual CI runs | Push branch to remote, wait for workflow run, verify all 3 jobs green |
| Branch protection configured correctly | TEST-02 (SC-3) | `gh api` branch protection requires repo admin access and actual CI run first | Run `gh api /repos/{owner}/{repo}/branches/main/protection` and verify 3 required checks listed |
| update-types workflow triggers and opens PR | REL-02 | Requires `workflow_dispatch` with API changes | Run `gh workflow run update-types.yml` and check for PR creation |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
