---
phase: 1
slug: compilable-bindings
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-26
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | dune runtest (alcotest) + dune build (Melange compile) |
| **Config file** | `dune-project`, `output/cf_workers_bindings/dune`, `output/cf_workers_bindings_test/dune` |
| **Quick run command** | `dune build` |
| **Full suite command** | `dune build && dune runtest` |
| **Estimated runtime** | ~30-60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `dune build`
- **After every plan wave:** Run `dune build && dune runtest`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** ~60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| OCaml switch + dune setup | 01 | 1 | PKG-01 | compile | `dune build` | ⬜ pending |
| Stream type qualification | 01 | 1 | BIND-01 | compile | `dune build` | ⬜ pending |
| Cross-module ref resolution | 01 | 1 | BIND-01 | compile | `dune build` | ⬜ pending |
| Inheritance subtype emit | 01 | 1 | BIND-03 | compile | `dune build` | ⬜ pending |
| Bind module wiring | 01 | 2 | BIND-02 | compile | `dune build` | ⬜ pending |
| Test suite emission | 01 | 3 | TEST-01 | compile+test | `dune build && dune runtest` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `output/cf_workers_bindings/dune` — activated Melange library stanza (uncommented)
- [ ] `output/cf_workers_bindings_test/dune` — Melange test library stanza (new file)
- [ ] `dune-project` — `(using melange 0.1)` and `lang dune 3.18` added
- [ ] OCaml 5.4 switch with melange installed

*These must exist before any tasks can be verified.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Bind smart constructors are ergonomic | BIND-02 | Ergonomics not machine-checkable | Review generated Bind module in d1.ml, crypto.ml — constructors should have meaningful names not `of_1`, `of_2` |
| Inheritance chains make sense | BIND-03 | Semantic correctness | Check R2ObjectBody extends R2Object, DurableObjectStub extends RpcTarget — `type t = SuperModule.t` present |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
