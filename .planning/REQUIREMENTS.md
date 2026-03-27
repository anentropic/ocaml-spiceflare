# Requirements: spiceflare

**Defined:** 2026-03-26
**Core Value:** Consumers get up-to-date, idiomatic Melange bindings for the entire CF Workers API without hand-authoring or maintaining them

## v1 Requirements

### Binding Fixes (BIND)

- [x] **BIND-01**: Generated bindings compile in a Melange project — `ReadableStream` and `WritableStream` references are qualified to their correct module paths
- [x] **BIND-02**: Heterogeneous input unions emit `Bind` modules with typed smart constructors (complete `transform.ml` to emit what `binding_ast.ml` and `emit.ml` already support)
- [x] **BIND-03**: Single-inheritance class chains emit `type t = SuperModule.t` so OCaml consumers can use subclass values at supertype positions without manual casting

### Package Setup (PKG)

- [ ] **PKG-01**: Bindings library `dune` stanza is activated (uncommented) and `dune-project` includes `(using melange 0.1)` — bindings build with `dune build -p spiceflare`
- [x] **PKG-02**: Repo contains two separate opam packages: `spiceflare` (generated Melange bindings) and `spiceflare-codegen` (generator tool), with disjoint dependency trees
- [x] **PKG-03**: Both opam files have complete metadata: `authors`, `homepage`, `source`, `bug-reports`, `license`, `doc` fields populated
- [ ] **PKG-04**: `CHANGES.md` exists with initial release entry in dune-release-compatible format
- [x] **PKG-05**: `spiceflare` package constrains `ocaml >= 5.4 & < 5.5` and `melange >= 6.0.1`; `spiceflare-codegen` constrains `ocaml >= 5.4`

### Testing (TEST)

- [ ] **TEST-01**: Codegen emits a compile-checking test suite alongside the bindings — one test file per module that calls each external with correctly-typed arguments, verifying cross-module type resolution under Melange
- [ ] **TEST-02**: CI runs `dune build -p spiceflare` and `dune build -p spiceflare-codegen` on OCaml 5.4 in GitHub Actions, and both pass

### Documentation (DOCS)

- [ ] **DOCS-01**: `spiceflare` README covers: installation via opam, dune dependency setup, quick start example, JS entry-point shim snippet, summary of binding conventions (receiver-last, `Bind` modules, env access pattern)
- [ ] **DOCS-02**: odoc API reference for all generated modules is built by CI and deployed to GitHub Pages on every push to main
- [ ] **DOCS-03**: `spiceflare-codegen` `DEVELOP.md` is expanded to a full contributor guide: pipeline walkthrough, how to add a new CF service, how to update types, how to extend the generator

### Demo (DEMO)

- [ ] **DEMO-01**: Repo contains a deployable demo Cloudflare Worker with `wrangler.toml`, `worker.js` entry-point shim, and at least one `Worker.ml` OCaml source file
- [ ] **DEMO-02**: Demo Worker exercises: HTTP fetch handler, KV namespace read/write, D1 database query, R2 bucket operation, and typed env access via `Env.get_unsafe`

### Release (REL)

- [ ] **REL-01**: GitHub Actions release workflow triggers on semver git tag, runs `dune-release` to produce a tarball, GitHub Release, and opam-repository PR for both packages
- [ ] **REL-02**: `update-types.yml` CI workflow is updated to reflect the new two-package structure, regenerate both the bindings and the compile-checking test suite, and open a PR when the CF Workers API changes
- [ ] **REL-03**: Both `spiceflare` and `spiceflare-codegen` are submitted to `ocaml/opam-repository` via the first release

## v2 Requirements

### Binding Quality

- **QUAL-01**: Purpose-based overload disambiguation — replace numeric suffixes (`get_2`, `put_2`, `ai_search_3`) with semantic names derived from parameter type differences
- **QUAL-02**: Intersection type precision — map `T & U` to a more specific type than the current first-member truncation; emit a warning for unhandled cases
- **QUAL-03**: Iterable/AsyncIterable types — introduce a `Js_iterable.t` stub rather than collapsing to `T array`, preserving lazy/streaming semantics
- **QUAL-04**: Overrides layer integration — consult `cloudflare/workers-types` overrides for generics and overloads that the RTTI system doesn't capture

## Out of Scope

| Feature | Reason |
|---------|--------|
| OCaml wrapper layer (typed routing, Request variants, Ctx helpers) | Consumers build this per project; raw bindings are the correct boundary |
| npm publishing of JS entry-point shim | Import path (`./_build/default/...`) is project-specific; documented as a 3-line copy-paste snippet instead |
| Cloudflare REST API bindings | Separate domain, separate package |
| ReasonML syntax output | OCaml syntax is the default; different ecosystem |
| Wasm bindings | Separate runtime path |
| Separate demo repository | In-repo demo is kept in sync automatically |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BIND-01 | Phase 1 | Complete |
| BIND-02 | Phase 1 | Complete |
| BIND-03 | Phase 1 | Complete |
| PKG-01 | Phase 1 | Pending |
| PKG-02 | Phase 2 | Complete |
| PKG-03 | Phase 2 | Complete |
| PKG-04 | Phase 4 | Pending |
| PKG-05 | Phase 2 | Complete |
| TEST-01 | Phase 1 | Pending |
| TEST-02 | Phase 3 | Pending |
| DOCS-01 | Phase 4 | Pending |
| DOCS-02 | Phase 4 | Pending |
| DOCS-03 | Phase 4 | Pending |
| DEMO-01 | Phase 5 | Pending |
| DEMO-02 | Phase 5 | Pending |
| REL-01 | Phase 6 | Pending |
| REL-02 | Phase 3 | Pending |
| REL-03 | Phase 6 | Pending |

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0

---
*Requirements defined: 2026-03-26*
*Last updated: 2026-03-26 after roadmap creation*
