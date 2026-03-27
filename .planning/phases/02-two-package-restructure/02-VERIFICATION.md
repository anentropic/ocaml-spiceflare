---
phase: 02-two-package-restructure
verified: 2026-03-27T12:00:00Z
status: passed
score: 3/3 requirements verified
gaps: []
---

# Phase 2: Two-Package Restructure Verification Report

**Phase Goal:** Split the single-package spiceflare repo into two independent opam packages: `spiceflare` (Melange bindings, no codegen deps) and `spiceflare-codegen` (generator CLI, no Melange dep).
**Verified:** 2026-03-27
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `dune build -p spiceflare` succeeds independently | VERIFIED | Build completed with zero errors or output |
| 2 | `dune build -p spiceflare-codegen` succeeds independently | VERIFIED | Build completed with zero errors or output |
| 3 | `spiceflare.opam` contains no yojson or alcotest | VERIFIED | grep confirms neither name present |
| 4 | `spiceflare-codegen.opam` contains no melange | VERIFIED | grep confirms melange not present |
| 5 | Both opam files pass `opam lint` with zero errors/warnings | VERIFIED | Both print "Passed." |
| 6 | Both files contain all required metadata fields | VERIFIED | authors, maintainer, license, homepage, bug-reports, doc all present |
| 7 | `spiceflare.opam` has `ocaml >= 5.4` open-ended | VERIFIED | `"ocaml" {>= "5.4"}` — no upper bound |
| 8 | `spiceflare.opam` has `melange >= 6.0.1` | VERIFIED | `"melange" {>= "6.0.1"}` |
| 9 | `spiceflare-codegen.opam` has `ocaml >= 5.4` open-ended | VERIFIED | `"ocaml" {>= "5.4"}` — no upper bound |

**Score:** 9/9 truths verified

---

## Requirement Results

### PKG-02: Package Isolation

| Check | Result |
|-------|--------|
| `dune build -p spiceflare` succeeds independently | PASS |
| `dune build -p spiceflare-codegen` succeeds independently | PASS |
| `spiceflare.opam` does NOT contain yojson | PASS |
| `spiceflare.opam` does NOT contain alcotest | PASS |
| `spiceflare-codegen.opam` does NOT contain melange | PASS |

**PKG-02: SATISFIED**

### PKG-03: opam Metadata

Both files pass `opam lint` with zero errors and zero warnings:

```
spiceflare.opam: Passed.
spiceflare-codegen.opam: Passed.
```

Both files contain all required fields:

| Field | spiceflare.opam | spiceflare-codegen.opam |
|-------|----------------|------------------------|
| authors | Paul J. Lucas | Paul J. Lucas |
| maintainer | Paul J. Lucas <paul@lucasmail.org> | Paul J. Lucas <paul@lucasmail.org> |
| license | ISC | ISC |
| homepage | https://github.com/paul-j-lucas/spiceflare | https://github.com/paul-j-lucas/spiceflare |
| bug-reports | https://github.com/paul-j-lucas/spiceflare/issues | https://github.com/paul-j-lucas/spiceflare/issues |
| doc | https://paul-j-lucas.github.io/spiceflare/ | https://paul-j-lucas.github.io/spiceflare/ |

**PKG-03: SATISFIED**

### PKG-05: Version Constraints

| Check | Value | Result |
|-------|-------|--------|
| `spiceflare.opam` ocaml constraint | `{>= "5.4"}` | PASS — open-ended, no upper bound |
| `spiceflare.opam` melange constraint | `{>= "6.0.1"}` | PASS |
| `spiceflare-codegen.opam` ocaml constraint | `{>= "5.4"}` | PASS — open-ended, no upper bound |

**PKG-05: SATISFIED**

---

## Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `spiceflare.opam` | VERIFIED | Generated from dune-project; melange >= 6.0.1, ocaml >= 5.4, no codegen deps |
| `spiceflare-codegen.opam` | VERIFIED | Generated from dune-project; yojson >= 2.0, alcotest with-test, ocaml >= 5.4, no melange |
| `dune-project` | VERIFIED | Two `(package ...)` stanzas with shared global metadata |
| `lib/dune` | VERIFIED | `(package spiceflare-codegen)` attributed correctly |
| `bin/dune` | VERIFIED | `(public_name spiceflare-codegen)` + `(package spiceflare-codegen)` |
| `test/dune` | VERIFIED | `(package spiceflare-codegen)` attributed correctly |
| `output/cf_workers_bindings/dune` | VERIFIED | `(public_name spiceflare)` — package inferred, no redundant (package ...) |
| `output/cf_workers_bindings_test/dune` | VERIFIED | `(package spiceflare)` attributed correctly |

---

## Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| `cf_workers_bindings` library | `spiceflare` package | `(public_name spiceflare)` in output/cf_workers_bindings/dune | WIRED |
| `spiceflare_lib` library | `spiceflare-codegen` package | `(package spiceflare-codegen)` in lib/dune | WIRED |
| `main` executable | `spiceflare-codegen` package | `(public_name spiceflare-codegen)` in bin/dune | WIRED |
| `test_all` test | `spiceflare-codegen` package | `(package spiceflare-codegen)` in test/dune | WIRED |
| `melange.emit` test target | `spiceflare` package | `(package spiceflare)` in output/cf_workers_bindings_test/dune | WIRED |

---

## Anti-Patterns Found

None.

---

## Human Verification Required

None. All verification criteria are mechanically checkable and have passed.

---

## Commits

| Hash | Description |
|------|-------------|
| `9a6c17d` | feat(pkg): split into spiceflare and spiceflare-codegen packages |
| `4b32eb2` | feat(pkg): regenerate opam files with complete metadata |

---

## Summary

Phase 2 goal is fully achieved. The repository is cleanly split into two independent opam packages:

- `spiceflare` — Melange bindings only (`melange >= 6.0.1`, `ocaml >= 5.4`; no codegen deps)
- `spiceflare-codegen` — generator CLI only (`yojson >= 2.0`, `alcotest`, `ocaml >= 5.4`; no Melange dep)

Both packages build independently, pass `opam lint` with zero warnings, carry complete opam metadata, and have all dune stanzas correctly attributed. All three requirements (PKG-02, PKG-03, PKG-05) are satisfied.

---

_Verified: 2026-03-27_
_Verifier: Claude (gsd-verifier)_
