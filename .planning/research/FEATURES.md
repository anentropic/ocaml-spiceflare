# Feature Landscape

**Domain:** OCaml/Melange auto-generated bindings library (Cloudflare Workers)
**Researched:** 2026-03-26
**Overall confidence:** HIGH (based on direct inspection of melange-community repos, opam packaging docs, gen_js_api patterns)

## Table Stakes

Features consumers expect from a published Melange bindings library. Missing any of these means the package will not be adopted -- users will copy-paste from the generated output instead of depending on the opam package.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Bindings compile under Melange** | If `dune build` fails, nothing else matters. The commented-out dune stanza is the #1 blocker. | High | Requires fixing ReadableStream/WritableStream qualification, uncommenting dune stanza, resolving all type errors across ~45 modules |
| **opam package with correct metadata** | Every melange-community library (melange-fetch, melange-webapi, melange-json, cf_workers) uses `(generate_opam_files true)` in dune-project with full metadata: source, homepage, bug-reports, authors, maintainers, license, synopsis, description | Low | Already partially done -- dune-project exists but is missing `(source ...)`, `(homepage ...)`, `(bug_reports ...)`, `(authors ...)`, `(maintainers ...)` fields and the `(using melange 0.1)` stanza |
| **Melange version constraint in depends** | All Melange bindings libraries pin `(melange (>= X.Y.Z))`. Without this, users hit cryptic build failures. melange-fetch requires `>= 5.0.0`, melange-webapi requires `>= 6.0.0`, cf_workers requires `>= 5.0.1` | Low | Must determine which Melange version spiceflare targets and add the constraint |
| **`(modes melange)` library stanza** | Standard pattern: `(library (name cf_workers_bindings) (public_name spiceflare) (modes melange))`. Without `public_name`, opam cannot expose the library | Low | Currently commented out entirely |
| **README with installation + usage** | Every melange-community library has: (1) what it is, (2) `opam install X`, (3) add to dune `(libraries X)`, (4) minimal code example. melange-fetch and melange-webapi both follow this exact pattern | Med | Need OCaml-syntax examples showing pipe-operator usage with the `[@mel.this]` receiver-last convention |
| **CHANGES.md / CHANGELOG.md** | Every opam-published library has one. `dune-release` reads it for release notes. melange-fetch uses CHANGES.md, melange-webapi uses CHANGELOG.md. Format: `## version` then bullet list | Low | Required for `dune-release` automation |
| **License file** | Already present (LICENSE). Standard requirement | Done | MIT license already in repo |
| **Two separate opam packages** | `spiceflare` (bindings) and `spiceflare-codegen` (generator). Consumers should only need to depend on the bindings, not the codegen toolchain. cf_workers does this as a single package; melange-json splits into melange-json + melange-json-native | Med | Requires restructuring dune-project with two `(package ...)` stanzas and separate library/executable targets |
| **CI that builds the bindings under Melange** | melange-fetch tests across OCaml 5.1.x + 5.2.x on macOS + Ubuntu. At minimum: checkout, setup-ocaml, install deps, `dune build` | Low | Current CI only tests the codegen (native OCaml), not the generated bindings (Melange mode) |
| **Versioning tied to upstream API** | The `4.20260317.1` version scheme (matching @cloudflare/workers-types) is correct and expected. Consumers need to know which CF Workers API version the bindings cover | Done | Already implemented in dune-project version field |

## Differentiators

Features that set spiceflare apart from hand-authored alternatives (cf_workers) and make the auto-generated approach compelling.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Codegen-emitted compile-checking test suite** | The generator knows every binding signature and can emit a test file per module that exercises every `external` declaration. This is the standard pattern in the ecosystem -- melange-webapi has ~50 test files that just call each binding with `let _ = fn(args)` to verify type-checking. gen_js_api uses snapshot testing + "successfully compiled" checks. The codegen can produce these automatically, guaranteeing 100% surface coverage -- impossible to maintain by hand at 45+ modules | High | This is the single most impactful differentiator. Hand-authored test suites always lag; generated ones are always complete. Pattern: `(melange.emit (target tests) (libraries cf_workers_bindings))` with one test file per module |
| **Full API surface coverage (~45 modules)** | cf_workers covers ~8 modules (ai, d1, headers, request, workers, ctx, promise_utils). spiceflare covers ~45. Automated regeneration means new CF services get bindings immediately | Done | Already achieved by codegen |
| **Automated weekly regeneration with PR** | The `update-types.yml` workflow is already built and handles: fetch latest types, extract IR, regenerate, diff, open PR. No other Melange bindings library has this | Done | Already implemented |
| **In-repo demo CF Worker** | A working `examples/` directory that deploys to Cloudflare Workers. melange-fetch has `examples/ocaml_examples.ml` + `examples/reason_examples.re`. melange-webapi has `examples/dom_example.re`. An actual deployable Worker that exercises KV, D1, fetch, and env would prove the bindings work end-to-end | Med | Needs: wrangler.toml, worker.js shim, OCaml handler module, dune stanza with `(melange.emit ...)`, esbuild bundling. Should be buildable with `dune build` but deployment requires a CF account |
| **odoc API reference** | `dune build @doc` generates HTML from `(** ... *)` doc comments. The codegen already preserves JSDoc comments from the IR. Having searchable API docs with cross-references is valuable for a 45-module library | Med | Requires: (1) `odoc` in depends with `{with-doc}`, (2) doc comments on types and externals (partially done via JSDoc preservation), (3) `index.mld` page for the package |
| **Per-module usage snippets in docs** | Beyond odoc, showing "here's how to use KV" or "here's how to make a fetch request" in README or a usage guide. The pipe-operator convention (`header |> Headers.set "content-type" "application/json"`) is non-obvious to newcomers | Med | 5-8 focused examples covering the most common CF Workers patterns |
| **GitHub Releases with dune-release-action** | `davesnx/dune-release-action` automates: tag push triggers release, creates GitHub Release, submits opam-repository PR. Clean CI pipeline: tag -> build -> test -> release | Low | Configuration-only: add workflow file, set up GH_TOKEN secret, ensure CHANGES.md format is correct |
| **Snapshot tests for codegen output stability** | gen_js_api pattern: run codegen, diff output against committed expected files. Detects unintentional codegen regressions. `(rule (alias runtest) (action (diff expected/kv.ml output/cf_workers_bindings/kv.ml)))` | Med | Requires committing a set of "expected" output files and adding dune diff rules. Valuable because codegen changes can silently alter the public API |

## Anti-Features

Features to explicitly NOT build. Each has a reason based on project scope and ecosystem norms.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **OCaml wrapper layer** (typed routing, Request variants, Ctx helpers) | Explicitly out of scope per PROJECT.md. Consumers build this per project. cf_workers includes a thin `ctx.ml` and `promise_utils.ml` but those are project-level utilities, not binding concerns | Document the intended layering (raw bindings -> user wrapper -> application) in README |
| **npm package publishing** | The JS shim is 3 lines and project-specific (import path depends on `_build/default/...`). No Melange bindings library publishes to npm -- they all go through opam only | Document the shim as a copy-paste snippet in README |
| **Runtime tests against actual CF Workers APIs** | Requires a Cloudflare account, wrangler authentication, and running infrastructure. Too fragile for CI. No bindings library in the ecosystem tests against live APIs | Compile-checking tests (type-check under Melange) are sufficient. The demo app serves as a manual integration test |
| **ReasonML syntax output** | OCaml syntax is the Melange default. melange-webapi uses Reason internally but that's legacy. New Melange libraries use OCaml syntax. Supporting both doubles maintenance | Stick with OCaml syntax. Reason users can read OCaml |
| **Nix flake for the bindings package** | melange-fetch and melange-webapi include flake.nix but it's for development convenience, not required for consumers. opam is the distribution channel | Include a simple flake.nix for contributors only if time permits; it's not a release requirement |
| **`opam-check-npm-deps` / depexts for npm packages** | spiceflare bindings have zero npm runtime dependencies -- they bind to APIs available in the CF Workers runtime, not npm packages. The `depexts` pattern is for libraries that wrap npm packages (like melange-json wrapping `@glennsl/bs-json`) | Document that no npm dependencies are needed; the CF Workers runtime provides all bound APIs |
| **Subtyping / implementation inheritance** (melange-webapi style) | melange-webapi uses complex phantom type subtyping and `include Impl` patterns because the DOM has deep inheritance hierarchies. CF Workers APIs are flat -- classes don't have deep inheritance. Each module is self-contained | Keep the current flat module structure. Each generated `.ml` file is independent |
| **PPX preprocessing** | Some Melange libraries use `(preprocess (pps melange.ppx))` for JSX or other PPX transforms. Pure `external` bindings don't need preprocessing | Keep the library stanza clean: `(library (name ...) (public_name ...) (modes melange))` with no `(preprocess ...)` |
| **`.mli` interface files for generated bindings** | gen_js_api generates from `.mli` to `.ml`. spiceflare generates `.ml` files directly. Adding `.mli` files would double the generated output for no benefit -- the `.ml` files already expose exactly the right public API since everything is `external` or `type` declarations | If consumers need to hide internals, they can add their own `.mli` in a wrapper library |

## Feature Dependencies

```
Fix compile blockers (ReadableStream/WritableStream)
    |
    v
Uncomment dune library stanza + add (modes melange) + public_name
    |
    +---> Compile-checking test suite (needs compilable bindings)
    |         |
    |         v
    |    CI: Melange build step (needs tests to run)
    |
    +---> Demo CF Worker (needs compilable bindings)
    |
    +---> odoc generation (needs compilable bindings)
    |
    v
Two-package restructure (spiceflare + spiceflare-codegen)
    |
    +---> opam metadata completion (source, homepage, etc.)
    |         |
    |         v
    |    CHANGES.md (needed for dune-release)
    |         |
    |         v
    |    dune-release-action CI workflow (needs metadata + changelog)
    |         |
    |         v
    |    opam publish
    |
    +---> Snapshot tests for codegen (independent of bindings compilation)

README + usage guide (can be written in parallel with anything)
```

## MVP Recommendation

The critical path to a publishable opam package:

### Priority 1 -- Unblock compilation (prerequisite for everything)

1. **Fix compile blockers** -- qualify ReadableStream/WritableStream references, resolve any other type errors across the 45 modules
2. **Uncomment and complete dune library stanza** -- `(library (name cf_workers_bindings) (public_name spiceflare) (modes melange))`
3. **Add `(using melange 0.1)` to dune-project** -- required for `(modes melange)` to work

### Priority 2 -- Publishable package

4. **Two-package restructure** -- separate `spiceflare` (bindings) from `spiceflare-codegen` (generator) in dune-project
5. **Complete opam metadata** -- source, homepage, bug_reports, authors, maintainers, melange version constraint
6. **CHANGES.md** -- initial release notes
7. **README with installation + usage examples** -- follow the melange-fetch pattern: what, install, dune config, code example

### Priority 3 -- Quality signals

8. **Codegen-emitted compile-checking test suite** -- one test file per module, `let _ = fn(args)` pattern from melange-webapi
9. **CI Melange build step** -- extend ci.yml to also build bindings under Melange
10. **odoc API reference** -- `(odoc ...)` stanza, doc comments, index.mld

### Defer

- **Demo CF Worker**: Valuable but not required for initial opam publish. Can be added in a follow-up release. Medium complexity due to wrangler config, esbuild bundling, and the JS shim
- **Snapshot tests for codegen stability**: Nice-to-have for maintainers, not required for consumers
- **dune-release-action automation**: Can publish first release manually with `opam-publish`, automate subsequent releases

## Sources

- [melange-fetch repository](https://github.com/melange-community/melange-fetch) -- dune-project structure, README pattern, examples, CHANGES.md format, CI workflow (HIGH confidence)
- [melange-webapi repository](https://github.com/melange-community/melange-webapi) -- compile-checking test pattern (~50 test files using `let _ = fn(args)`), CHANGELOG.md, subtyping patterns, library structure (HIGH confidence)
- [melange-json repository](https://github.com/melange-community/melange-json) -- multi-package dune-project pattern, test dependencies (HIGH confidence)
- [adrianparvino/cf_workers](https://github.com/adrianparvino/cf_workers) -- prior art for CF Workers Melange bindings, minimal package structure (HIGH confidence)
- [gen_js_api repository](https://github.com/LexiFi/gen_js_api) -- auto-generated bindings test patterns: snapshot testing via `(diff expected/... actual/...)` and compile-checking via library build (HIGH confidence)
- [melange-community/bindings](https://github.com/melange-community/bindings) -- ecosystem conventions for binding libraries, tools for generating bindings (MEDIUM confidence)
- [Melange package management docs](https://melange.re/v6.0.1/package-management.html) -- opam packaging patterns, depexts for npm deps, library modes (HIGH confidence)
- [opam packaging guide](https://opam.ocaml.org/doc/Packaging.html) -- metadata requirements, versioning, publishing workflow (HIGH confidence)
- [dune-release-action](https://github.com/davesnx/dune-release-action) -- automated opam publishing from GitHub Actions (HIGH confidence)
- [odoc documentation](https://ocaml.org/docs/generating-documentation) -- `dune build @doc` workflow, index.mld convention (HIGH confidence)
