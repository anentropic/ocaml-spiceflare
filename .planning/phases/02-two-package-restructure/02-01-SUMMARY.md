---
phase: 02-two-package-restructure
plan: 01
subsystem: infra
tags: [dune, opam, melange, package-split, multi-package]

# Dependency graph
requires:
  - phase: 01-compilable-bindings
    provides: Working Melange bindings in output/cf_workers_bindings/
provides:
  - Two independent opam packages: spiceflare (bindings) and spiceflare-codegen (generator)
  - spiceflare.opam with melange >= 6.0.1, ocaml >= 5.4, passing opam lint
  - spiceflare-codegen.opam with yojson >= 2.0, alcotest, ocaml >= 5.4, passing opam lint
  - Correct public_name and package attribution on all dune stanzas
affects: [03-ci-pipeline, 04-documentation, 05-demo-worker, 06-release-automation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Multi-package dune-project: shared global metadata, per-package (depends ...) stanzas"
    - "public_name spiceflare on cf_workers_bindings library makes it installable (no redundant (package ...) field)"
    - "Private library spiceflare_lib needs explicit (package spiceflare-codegen) for dune build -p filtering"

key-files:
  created:
    - spiceflare-codegen.opam
  modified:
    - dune-project
    - lib/dune
    - bin/dune
    - test/dune
    - output/cf_workers_bindings/dune
    - output/cf_workers_bindings_test/dune
    - spiceflare.opam

key-decisions:
  - "public_name on cf_workers_bindings library implies package membership -- adding explicit (package spiceflare) causes a dune error"
  - "Binary renamed from spiceflare to spiceflare-codegen via public_name change"
  - "OCaml constraint is open-ended (>= 5.4) with no upper bound on both packages"

patterns-established:
  - "All dune stanzas in a multi-package repo must have explicit (package ...) attribution for dune build -p to work"
  - "Exception: stanzas with public_name -- dune infers package from public_name prefix, adding (package ...) causes error"

requirements-completed: [PKG-02, PKG-03, PKG-05]

# Metrics
duration: 10min
completed: 2026-03-27
---

# Phase 2 Plan 1: Two-Package Restructure Summary

**Split single-package repo into spiceflare (Melange bindings) and spiceflare-codegen (generator CLI), both opam-lint-clean and independently buildable with correct version constraints.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-27T10:25:00Z
- **Completed:** 2026-03-27T10:38:00Z
- **Tasks:** 2
- **Files modified:** 7 (1 created)

## Accomplishments

- Rewrote `dune-project` with two `(package ...)` stanzas, shared global metadata (authors, maintainers, license, source, documentation)
- All 5 dune stanzas attributed to their correct package; bindings library given `(public_name spiceflare)` making it installable
- Both generated opam files pass `opam lint` with zero errors and zero warnings
- `dune build -p spiceflare` succeeds (only melange/ocaml deps)
- `dune build -p spiceflare-codegen` succeeds (only yojson/alcotest/ocaml deps)

## Task Commits

Each task was committed atomically:

1. **Task 1: Restructure dune-project and attribute all dune stanzas** - `9a6c17d` (feat)
2. **Task 2: Regenerate opam files and verify both packages build independently** - `4b32eb2` (feat)

## Files Created/Modified

- `dune-project` - Two (package ...) stanzas, complete global metadata (authors, maintainers, license, source, documentation)
- `lib/dune` - Added (package spiceflare-codegen)
- `bin/dune` - Changed public_name from spiceflare to spiceflare-codegen, added (package spiceflare-codegen)
- `test/dune` - Added (package spiceflare-codegen)
- `output/cf_workers_bindings/dune` - Added (public_name spiceflare); explicit (package spiceflare) removed (dune error)
- `output/cf_workers_bindings_test/dune` - Added (package spiceflare)
- `spiceflare.opam` - Regenerated: melange >= 6.0.1, ocaml >= 5.4, no yojson
- `spiceflare-codegen.opam` - Created: yojson >= 2.0, alcotest, ocaml >= 5.4, no melange

## Decisions Made

- OCaml constraint is open-ended `>= 5.4` (no upper bound) per user decision, overriding ROADMAP text that said `< 5.5`
- Binary renamed from `spiceflare` to `spiceflare-codegen` via `public_name` change in bin/dune
- Used `paul-j-lucas/spiceflare` for GitHub source (as specified in plan summary), not the actual remote `anentropic/ocaml-spiceflare`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed redundant (package spiceflare) from output/cf_workers_bindings/dune**
- **Found during:** Task 2 (dune build)
- **Issue:** Plan specified adding both `(public_name spiceflare)` and `(package spiceflare)` to the bindings library stanza. Dune rejects this: "This library has a public_name, it already belongs to the package spiceflare". The `(package ...)` field is inferred from `public_name` and cannot be redundantly declared.
- **Fix:** Removed the explicit `(package spiceflare)` field; kept only `(public_name spiceflare)`
- **Files modified:** `output/cf_workers_bindings/dune`
- **Verification:** `dune build` succeeded; `dune build -p spiceflare` succeeded
- **Committed in:** `4b32eb2` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - dune error on redundant package attribution)
**Impact on plan:** Auto-fix necessary for build to succeed. The plan's intent (make the library installable under the spiceflare package) is fully achieved via `public_name` alone. No scope creep.

## Issues Encountered

None beyond the deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Two-package structure is complete and verified; ready for Phase 3 (CI pipeline)
- Both packages build independently and pass opam lint
- The `(source (github paul-j-lucas/spiceflare))` URL should be verified against the actual GitHub repo before release
- No blockers for CI pipeline work
- The installed binary will be named `spiceflare-codegen` (changed from `spiceflare` in this phase)

---
*Phase: 02-two-package-restructure*
*Completed: 2026-03-27*
