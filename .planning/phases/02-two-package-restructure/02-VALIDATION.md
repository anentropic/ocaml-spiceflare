---
phase: 2
slug: two-package-restructure
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-27
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dune build + opam lint (CLI verification) |
| **Config file** | dune-project |
| **Quick run command** | `dune build -p spiceflare && dune build -p spiceflare-codegen` |
| **Full suite command** | `dune build -p spiceflare && dune build -p spiceflare-codegen && opam lint spiceflare.opam && opam lint spiceflare-codegen.opam` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `dune build -p spiceflare && dune build -p spiceflare-codegen`
- **After every plan wave:** Run full suite command above
- **Before `/gsd:verify-work`:** Full suite must be green with `opam lint` showing 0 errors
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | PKG-02 | build | `dune build -p spiceflare-codegen` | ✅ | ⬜ pending |
| 2-01-02 | 01 | 1 | PKG-02 | build | `dune build -p spiceflare` | ✅ | ⬜ pending |
| 2-01-03 | 01 | 1 | PKG-03 | lint | `opam lint spiceflare.opam && opam lint spiceflare-codegen.opam` | ✅ | ⬜ pending |
| 2-01-04 | 01 | 1 | PKG-05 | grep | `grep 'ocaml.*5.4' spiceflare.opam` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- Existing `dune` and `opam` CLI tools are available in the environment — no installation needed.

*Existing infrastructure covers all phase requirements.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `dune build -p spiceflare` has no codegen deps in solve | PKG-02 | Requires inspecting `_opam` solver output | Run `opam install --dry-run spiceflare.opam` in a fresh switch and verify `yojson` is not listed |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
