# Roadmap: spiceflare

## Overview

spiceflare goes from "codegen works but output doesn't compile" to "two published opam packages with tests, docs, and a demo Worker." The critical path is strict: bindings must compile before anything else can be validated. From there, the repo splits into two packages, CI verifies both, documentation and a demo prove the bindings work end-to-end, and release automation publishes to opam-repository.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Compilable Bindings** - Fix codegen blockers, activate dune stanza, and emit compile-checking test suite so all ~45 generated modules type-check under Melange
- [ ] **Phase 2: Two-Package Restructure** - Split repo into `spiceflare` (bindings) and `spiceflare-codegen` (generator) opam packages with correct metadata and dependency isolation
- [ ] **Phase 3: CI and Testing** - CI builds and tests both packages independently on OCaml 5.4, and the update-types workflow reflects the new structure
- [ ] **Phase 4: Documentation** - README, odoc API reference, contributor guide, and CHANGES.md are complete and CI-verified
- [ ] **Phase 5: Demo Worker** - A deployable Cloudflare Worker in-repo exercises KV, D1, R2, fetch, and env bindings via Melange + Wrangler
- [ ] **Phase 6: Release Automation** - Tag-triggered GitHub Actions workflow runs dune-release, and both packages are submitted to opam-repository

## Phase Details

### Phase 1: Compilable Bindings
**Goal**: Generated bindings compile under Melange and a codegen-emitted test suite verifies every module type-checks
**Depends on**: Nothing (first phase)
**Requirements**: BIND-01, BIND-02, BIND-03, PKG-01, TEST-01
**Success Criteria** (what must be TRUE):
  1. `dune build` succeeds with all ~45 generated binding modules compiled under Melange (no unresolved type errors)
  2. Codegen emits a test file per module that calls each external with correctly-typed arguments, and `dune build @runtest` passes for the test suite
  3. Subclass values can be used at supertype positions in OCaml without manual casting (inheritance chains emit `type t = SuperModule.t`)
  4. Heterogeneous input unions in binding parameters use typed `Bind` smart constructors instead of `'a Js.t`
**Plans:** 3 plans

Plans:
- [x] 01-01-PLAN.md -- Core codegen fixes: cross-module type qualification, type parameter threading, forward-reference topo sort, stream type resolution
- [ ] 01-02-PLAN.md -- Inheritance aliases (BIND-03) and Bind module generation (BIND-02)
- [ ] 01-03-PLAN.md -- Melange infrastructure activation, test suite emission, regeneration, and compile verification

### Phase 2: Two-Package Restructure
**Goal**: Repo contains two independent opam packages with correct metadata so consumers can install bindings without pulling in codegen dependencies
**Depends on**: Phase 1
**Requirements**: PKG-02, PKG-03, PKG-05
**Success Criteria** (what must be TRUE):
  1. `dune build -p spiceflare` succeeds and produces only the Melange bindings library (no codegen dependencies in the solve)
  2. `dune build -p spiceflare-codegen` succeeds and produces the generator tool independently
  3. Both opam files pass `opam lint` with no errors and contain all required metadata fields (authors, homepage, source, bug-reports, license, doc)
  4. `spiceflare` declares `ocaml >= 5.4 & < 5.5` and `melange >= 6.0.1`; `spiceflare-codegen` declares `ocaml >= 5.4`
**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: CI and Testing
**Goal**: CI verifies both packages build and test cleanly on every push, and the automated types-update workflow works with the new two-package structure
**Depends on**: Phase 2
**Requirements**: TEST-02, REL-02
**Success Criteria** (what must be TRUE):
  1. GitHub Actions runs `dune build -p spiceflare` and `dune build -p spiceflare-codegen` on OCaml 5.4 on every push, and both pass
  2. The `update-types.yml` workflow regenerates bindings and the compile-checking test suite, and opens a PR when the CF Workers API changes
  3. CI failure on binding compile regression blocks merge (status check required)
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Documentation
**Goal**: Consumers can install and use the bindings from README instructions alone, contributors can extend the codegen from DEVELOP.md, and API docs are published
**Depends on**: Phase 2
**Requirements**: DOCS-01, DOCS-02, DOCS-03, PKG-04
**Success Criteria** (what must be TRUE):
  1. `spiceflare` README contains installation via opam, dune dependency setup, quick-start example, JS shim snippet, and binding convention summary
  2. `dune build @doc` produces odoc API reference for all generated modules, and CI deploys it to GitHub Pages on push to main
  3. `DEVELOP.md` covers the full codegen pipeline, how to add a new CF service, how to update types, and how to extend the generator
  4. `CHANGES.md` exists with an initial release entry in dune-release-compatible format
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD
- [ ] 04-03: TBD

### Phase 5: Demo Worker
**Goal**: A working Cloudflare Worker proves the bindings are usable end-to-end in a real deployment scenario
**Depends on**: Phase 1
**Requirements**: DEMO-01, DEMO-02
**Success Criteria** (what must be TRUE):
  1. `demo/` directory contains `wrangler.toml`, `worker.js` entry-point shim, and at least one `Worker.ml` OCaml source file that compiles under Melange
  2. The demo Worker handles HTTP fetch requests and exercises KV read/write, D1 query, R2 bucket operation, and typed env access via `Env.get_unsafe`
  3. `wrangler dev --local` starts the demo worker and responds to HTTP requests without runtime errors
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

**UI hint**: yes

### Phase 6: Release Automation
**Goal**: A git tag triggers automated publishing of both packages to opam-repository via GitHub Releases
**Depends on**: Phase 3, Phase 4, Phase 5
**Requirements**: REL-01, REL-03
**Success Criteria** (what must be TRUE):
  1. Pushing a semver git tag triggers a GitHub Actions workflow that runs `dune-release` to produce a tarball and GitHub Release
  2. The release workflow opens an opam-repository PR for both `spiceflare` and `spiceflare-codegen`
  3. Both packages install cleanly from opam in a fresh switch after the PR is merged
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6
Note: Phase 4 and Phase 5 can execute in parallel after their dependencies are met.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Compilable Bindings | 0/3 | Not started | - |
| 2. Two-Package Restructure | 0/2 | Not started | - |
| 3. CI and Testing | 0/2 | Not started | - |
| 4. Documentation | 0/3 | Not started | - |
| 5. Demo Worker | 0/2 | Not started | - |
| 6. Release Automation | 0/2 | Not started | - |
