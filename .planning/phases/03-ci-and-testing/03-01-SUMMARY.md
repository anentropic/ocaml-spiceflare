---
phase: 03-ci-and-testing
plan: 01
subsystem: ci
tags: [github-actions, ci, melange, ocaml, matrix-strategy]
dependency_graph:
  requires: []
  provides: [ci-matrix-build, melange-check-job, update-types-v8]
  affects: [.github/workflows/ci.yml, .github/workflows/update-types.yml]
tech_stack:
  added: []
  patterns: [matrix-strategy, fail-fast-false, dune-cache]
key_files:
  created: []
  modified:
    - .github/workflows/ci.yml
    - .github/workflows/update-types.yml
decisions:
  - OCaml 5.4.x selected for both workflows (up from 5.2.x)
  - Matrix strategy chosen over sequential builds for parallel package CI
  - melange-check separated into its own job (not folded into build matrix)
  - peter-evans/create-pull-request upgraded from v6 to v8
metrics:
  duration: "5m"
  completed: "2026-03-27"
  tasks_completed: 2
  files_modified: 2
---

# Phase 03 Plan 01: CI Workflow Updates Summary

Matrix CI with melange-check plus updated types workflow using spiceflare-codegen binary and peter-evans v8.

## What Was Done

### Task 1: Rewrite ci.yml

Replaced the single-job ci.yml with a two-job configuration:

- `build` job uses a matrix strategy (`fail-fast: false`) to run parallel builds for `spiceflare` and `spiceflare-codegen`, each installing deps with `--with-test` and running `dune build -p` and `dune runtest -p` scoped to the package.
- `melange-check` job is a separate job that installs deps without `--with-test` and runs `dune build @melange` to verify the generated bindings compile under Melange.
- Both jobs use OCaml 5.4.x and `dune-cache: true`.
- The old `dune build @doc` step was removed (documentation CI deferred to a later phase).

### Task 2: Update update-types.yml

Updated the scheduled update workflow with four changes:

1. `ocaml-compiler: 5.2.x` upgraded to `5.4.x`
2. Added `dune-cache: true` to the setup-ocaml step
3. `dune exec spiceflare` renamed to `dune exec spiceflare-codegen` to match the two-package binary name
4. Both `peter-evans/create-pull-request` usages (success path and failure path) upgraded from `@v6` to `@v8`
5. PR body updated to mention `output/cf_workers_bindings_test/` for updated compile-checking tests

## Deviations from Plan

None - plan executed exactly as written.

## Commits

- `79c4471`: feat(ci): split CI into parallel jobs with melange-check, update types workflow

## Self-Check: PASSED

- `.github/workflows/ci.yml` exists and contains all required patterns
- `.github/workflows/update-types.yml` exists and contains `spiceflare-codegen`, `5.4.x`, two `create-pull-request@v8` usages
- Commit `79c4471` present in git log
