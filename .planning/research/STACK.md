# Technology Stack

**Project:** spiceflare (milestone 2: packaging, docs, demo, CI)
**Researched:** 2026-03-26

## Recommended Stack

### Core Compiler & Build

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| OCaml | 5.2.x | Compiler for codegen tool + native tests | Already pinned in dune-project/CI. Melange 6.0.1-52 targets exactly `>=5.2 & <5.3`. Upgrading to 5.3/5.4 gains nothing for this project and risks dependency churn. | HIGH |
| Dune | >= 3.18 (lang 3.16 in dune-project is fine for declaration; installed 3.21+ satisfies runtime) | Build system | Melange 6.0.1-52 requires dune >= 3.18 at build time. The `(lang dune 3.16)` declaration in dune-project is the *minimum language version* and does not need to match the installed dune version. Keep `lang 3.16` unless a newer stanza is needed. | HIGH |
| Melange | 6.0.1-52 | OCaml-to-JS compiler for bindings | Latest stable release (Dec 2025). The `-52` suffix = OCaml 5.2 variant. Supports `(modes melange)` in library stanzas. Melange 6 removed `[@@deriving abstract]` in favor of `[@@deriving jsProperties, getSet]` -- verify generated bindings don't use deprecated forms. | HIGH |

### Melange Dune Plugin

| Setting | Value | Why | Confidence |
|---------|-------|-----|------------|
| `(using melange 0.1)` | Add to dune-project | Required to enable `(modes melange)` in library stanzas and `melange.emit` stanzas. The plugin version `0.1` is the only version -- it has not been bumped since introduction. | HIGH |
| `melange.ppx` | Preprocessor | Add `(preprocess (pps melange.ppx))` to the bindings library. Required for `[@mel.obj]`, `[@mel.send]`, and other FFI attributes used in the generated bindings. | HIGH |

### Packaging & Release

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| dune-release | 2.2.0 | Tag-to-opam-PR automation | Latest (Jan 2026). Supports multi-package repos (one tarball, multiple opam files). Has `--token` flag for CI use. Supports `--draft` for testing. The `dune-release check` command verifies prerequisites before starting. | HIGH |
| davesnx/dune-release-action | v1 | GitHub Actions wrapper for dune-release | Triggers on tag push, automates: changelog extraction, GitHub Release creation, opam-repository PR submission. Caveat: self-described as "half vibe-coded" -- test the workflow on a dry-run tag before relying on it. Fallback: script `dune-release` commands directly in CI. | MEDIUM |
| opam (generate_opam_files) | Already configured | Generate `.opam` files from `(package)` stanzas in dune-project | Already using `(generate_opam_files true)`. Need to add a second `(package (name spiceflare-codegen) ...)` stanza. Both `.opam` files will be auto-generated on `dune build`. | HIGH |

### Demo Worker Deployment

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| wrangler | 4.x (latest: 4.77.0) | Cloudflare Workers CLI | v4 is current (minor upgrade from v3, limited breaking changes). Dropped Node 16 support (we use Node 22, fine). `no_bundle = true` in wrangler.toml skips esbuild -- required because Melange already produces JS output. | HIGH |
| cloudflare/wrangler-action | v3 | CI deployment to CF Workers | Official GitHub Action. Supports custom wrangler version pinning, API token auth, and custom commands. | HIGH |
| esbuild | (via wrangler or standalone) | Bundle Melange JS output if needed | Wrangler v4 uses esbuild 0.24 internally. With `no_bundle = true`, wrangler skips it. If the Melange output needs bundling (multiple JS files into one entry), run esbuild separately in a `[build]` step. | MEDIUM |

### Documentation

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| odoc | 3.1.0 | API reference generation | Latest (Jul 2025). Major upgrade: search-by-type, global sidebar, breadcrumbs, media support, cross-package links, source code linking. Already a with-doc dependency. | HIGH |
| dune build @doc | Built-in | Triggers odoc | Standard workflow. Output lands in `_build/default/_doc/_html/`. | HIGH |
| actions/upload-pages-artifact | v4 | Package docs for GitHub Pages | Official GitHub action for Pages deployment. v4 required as of Jan 2025. | HIGH |
| actions/deploy-pages | v4 | Deploy to GitHub Pages | Companion to upload-pages-artifact. Must match v4+. | HIGH |

### Testing

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| alcotest | >= 1.7 (latest: 1.9.1) | Unit tests for codegen tool | Already in use. Keep for native OCaml tests of the codegen pipeline. | HIGH |
| Melange compile check (custom) | N/A | Verify generated bindings type-check | Not a library -- a `melange.emit` stanza that depends on the bindings library. If `dune build` succeeds, all bindings type-check under Melange. This is the compile-checking test suite mentioned in PROJECT.md. | HIGH |

### CI Infrastructure

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| ocaml/setup-ocaml | v3 | CI OCaml environment | Standard. Supports OCaml 5.2.x, dune caching, opam pin. Already in use. | HIGH |
| actions/setup-node | v4 | Node.js for extraction + wrangler | Already in use (Node 22). | HIGH |
| peter-evans/create-pull-request | v6 | Automated PR creation for type updates | Already in use for weekly IR update workflow. | HIGH |

### Formatting & Linting

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| ocamlformat | 0.27.0 | Code formatting | Already configured in `.ocamlformat`. Keep pinned -- version drift causes CI failures. | HIGH |

## Key Configuration: Two-Package dune-project

The current `dune-project` declares only `spiceflare`. It needs a second `(package)` stanza for `spiceflare-codegen`:

```lisp
(lang dune 3.16)
(using melange 0.1)

(name spiceflare)
(version 4.20260317.1)
(generate_opam_files true)

; Metadata fields (added once, shared)
(license MIT)
(source (github username/ocaml-spiceflare))
(authors "Author Name")
(maintainers "maintainer@example.com")

(package
 (name spiceflare)
 (synopsis "Melange bindings for the Cloudflare Workers API")
 (description "Type-safe OCaml/Melange external bindings for the full Cloudflare Workers runtime API surface.")
 (depends
  (ocaml (>= 5.2))
  (melange (>= 6.0))
  (dune (>= 3.18))))

(package
 (name spiceflare-codegen)
 (synopsis "Code generator for Cloudflare Workers Melange bindings")
 (description "Reads a JSON IR extracted from @cloudflare/workers-types and emits Melange .ml binding files.")
 (depends
  (ocaml (>= 5.2))
  (yojson (>= 2.0))
  (alcotest (and :with-test (>= 1.7)))))
```

**Key points:**
- `spiceflare` depends on `melange` (consumers need it to compile bindings) and `dune >= 3.18` (for melange plugin support)
- `spiceflare-codegen` does NOT depend on melange (it generates `.ml` files but doesn't compile them to JS)
- Both share the same version (tied to CF API versions)
- `(using melange 0.1)` is added at the top level to enable melange stanzas

## Key Configuration: Bindings Library dune File

The currently-commented-out `output/cf_workers_bindings/dune` should become:

```lisp
(library
 (name cf_workers_bindings)
 (public_name spiceflare)
 (modes melange)
 (preprocess (pps melange.ppx)))
```

**Key points:**
- `(public_name spiceflare)` makes this installable as the `spiceflare` opam package
- `(modes melange)` compiles only under Melange (not native OCaml)
- `(preprocess (pps melange.ppx))` is required for `[@mel.obj]`, `[@mel.send]`, etc.

## Key Configuration: Compile-Checking Test

Create a `test/melange_check/` directory with:

```lisp
; test/melange_check/dune
(melange.emit
 (target melange_check_output)
 (libraries spiceflare)
 (alias melange-check))
```

```ocaml
(* test/melange_check/check.ml *)
(* Import modules to verify they type-check *)
open Cf_workers_bindings
let _ = Kv.t
let _ = D1.t
(* ... one line per module *)
```

If `dune build @melange-check` succeeds, all bindings compile. This replaces traditional unit tests for binding correctness.

## Key Configuration: Demo Worker wrangler.toml

```toml
name = "spiceflare-demo"
main = "worker.js"
compatibility_date = "2026-03-01"
no_bundle = true

[build]
command = "opam exec -- dune build @melange-emit-demo"
watch_dir = "demo"

[[kv_namespaces]]
binding = "DEMO_KV"
id = "placeholder-for-local-dev"

[[d1_databases]]
binding = "DEMO_DB"
database_name = "demo"
database_id = "placeholder-for-local-dev"

[[r2_buckets]]
binding = "DEMO_R2"
bucket_name = "demo-bucket"
```

**Key points:**
- `no_bundle = true` because Melange already emits JS; wrangler's esbuild would mangle it
- `main` points to a hand-authored 3-line JS shim that imports Melange output
- `[build].command` runs dune to produce the Melange JS before deploy
- Binding IDs are placeholders for local dev (`wrangler dev --local`)

## Key Configuration: Documentation CI

```yaml
# .github/workflows/docs.yml (runs on main branch push)
- uses: ocaml/setup-ocaml@v3
  with:
    ocaml-compiler: 5.2.x
- run: opam install . --deps-only --with-doc
- run: opam exec -- dune build @doc
- uses: actions/upload-pages-artifact@v4
  with:
    path: _build/default/_doc/_html
- uses: actions/deploy-pages@v4
```

**Key points:**
- `--with-doc` installs odoc
- Output is in `_build/default/_doc/_html/`
- Uses the official GitHub Pages deployment actions (v4 required)
- Alternative: `peaceiris/actions-gh-pages@v3` (older pattern, still works)

## Key Configuration: Release CI

```yaml
# .github/workflows/release.yml (triggers on tag push)
on:
  push:
    tags: ['*']
permissions:
  contents: write
  pull-requests: write

steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0
  - uses: ocaml/setup-ocaml@v3
    with:
      ocaml-compiler: 5.2.x
  - run: opam install dune-release -y
  - uses: davesnx/dune-release-action@v1
    with:
      packages: spiceflare spiceflare-codegen
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Fallback (if dune-release-action is unreliable):**
```yaml
  - run: |
      opam exec -- dune-release distrib --skip-tests
      opam exec -- dune-release publish distrib --token ${{ secrets.GITHUB_TOKEN }}
      opam exec -- dune-release opam pkg
      opam exec -- dune-release opam submit --token ${{ secrets.GITHUB_TOKEN }}
```

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| OCaml version | 5.2.x | 5.3 or 5.4 | Melange versions are pinned to specific OCaml minor versions. 5.2 is stable, already in CI, and `melange.6.0.1-52` targets it exactly. No benefit to upgrading. |
| Melange version | 6.0.1-52 | 5.0.1-52 | Melange 6 is current. 5.x is behind on JS codegen quality. 6.0 removed `[@@deriving abstract]` but spiceflare uses `[@mel.obj]` which is unaffected. |
| Release tooling | dune-release 2.2 | opam-publish | opam-publish is lower-level. dune-release handles the full workflow: lint, distrib, GitHub Release, opam PR. Multi-package support is built in. |
| Release CI | davesnx/dune-release-action | Manual scripting | The action wraps the same commands but handles edge cases. If it proves flaky, fall back to direct `dune-release` commands (shown above). |
| Docs deployment | actions/upload-pages-artifact + deploy-pages | peaceiris/actions-gh-pages | The official GitHub actions are the current standard. peaceiris is older and third-party. Both work but official is preferred. |
| Docs generator | odoc 3.1 | Docusaurus, VitePress | odoc is the OCaml standard. For a bindings library, API docs are the primary deliverable. Prose documentation goes in `.mld` files within odoc. External static site generators add complexity without proportional value for this project. |
| Bundler | wrangler no_bundle + optional esbuild | webpack, rollup | Melange emits ES6 modules. Wrangler's built-in esbuild handles bundling if needed. No reason to introduce a separate bundler. |
| Test framework | Compile check via melange.emit | melange-jest, alcotest for bindings | Bindings are `external` declarations -- they have no runtime behavior to test. Type-checking IS the test. A `melange.emit` stanza that imports all modules verifies everything compiles. |
| Worker deploy CI | cloudflare/wrangler-action | Manual wrangler CLI | The official action handles auth, version pinning, and deployment URL output. |

## What NOT to Use

| Tool | Why Not |
|------|---------|
| `opam-publish` (standalone) | Lower-level than dune-release. dune-release subsumes it and adds changelog parsing, GitHub Release creation, and multi-package support. |
| `opam-monorepo` | For vendoring external dependencies into a monorepo. Not needed here -- this project's dependencies are standard opam packages. |
| `mel` CLI (Melange standalone) | Older Melange CLI tool. Dune integration via `(modes melange)` is the current standard. `mel` is not recommended for new projects. |
| `[@@deriving abstract]` | Removed in Melange 6.0. Use `[@@deriving jsProperties, getSet]` or `[@mel.obj]` instead. The codegen already uses `[@mel.obj]`. |
| `setup-ocaml` deploy-doc feature | Does not exist despite some forum mentions. The action has `lint-doc` but not `deploy-doc`. Use the standard `upload-pages-artifact` + `deploy-pages` pattern. |
| VitePress / Docusaurus for docs | Overkill for a bindings library. odoc 3 with `.mld` files covers API reference + prose guides. Save static site generators for projects with marketing pages. |
| `npm publish` for JS shim | The 3-line JS entry shim is project-specific (import path depends on `_build/` layout). Document it; don't publish it. |

## Installation

```bash
# Core development (already set up)
opam install ocaml.5.2.1 dune

# Bindings library dependencies
opam install melange.6.0.1-52

# Codegen tool dependencies
opam install yojson alcotest

# Release tooling
opam install dune-release.2.2.0

# Documentation
opam install odoc.3.1.0

# Demo worker (Node.js)
npm install -g wrangler@latest  # or: npm install --save-dev wrangler
```

## Version Pinning Strategy

| Package | Pin Strategy | Rationale |
|---------|-------------|-----------|
| OCaml | `5.2.x` in CI, `>= 5.2` in opam depends | Melange suffix locks us to a minor series |
| Melange | `>= 6.0` in opam depends | Allow patch upgrades; `-52` suffix auto-resolves based on OCaml version |
| Dune | `>= 3.18` in opam depends, `lang 3.16` in dune-project | Melange 6 needs 3.18+ at build time; lang version is the minimum syntax version |
| odoc | No pin (with-doc) | Always use latest; docs are not a runtime dependency |
| wrangler | Pin major in package.json: `^4.0.0` | v4 breaking changes are minor; stay current within major |
| ocamlformat | Pin exact in `.ocamlformat`: `0.27.0` | Version drift causes reformatting churn |

## Sources

- [opam: Melange versions](https://opam.ocaml.org/packages/melange/) -- version listing, dependency constraints (HIGH confidence)
- [opam: melange 6.0.1-52](https://opam.ocaml.org/packages/melange/melange.6.0.1-52/) -- exact OCaml/dune constraints (HIGH confidence)
- [Melange build system docs (v2)](https://melange.re/v2.0.0/build-system/) -- dune plugin config, library stanzas (HIGH confidence)
- [Dune stable: Melange compilation](https://dune.readthedocs.io/en/stable/melange.html) -- melange.emit, library modes (HIGH confidence, 403 on fetch but cross-verified)
- [Melange 6.0 Changes.md](https://github.com/melange-re/melange/blob/main/Changes.md) -- breaking changes, @deriving abstract removal (HIGH confidence)
- [Universal libraries in Dune preview](https://melange.re/blog/posts/dune-universal-libraries-preview) -- dual native/melange compilation (MEDIUM confidence, experimental)
- [dune-release on opam](https://opam.ocaml.org/packages/dune-release/) -- version 2.2.0 latest (HIGH confidence)
- [dune-release-action announcement](https://discuss.ocaml.org/t/ann-dune-release-action-automate-your-opam-package-releases-with-github-actions/17380) -- workflow pattern, caveats (MEDIUM confidence)
- [davesnx/dune-release-action](https://github.com/davesnx/dune-release-action) -- configuration options (MEDIUM confidence)
- [dune-release multi-package issue #442](https://github.com/tarides/dune-release/issues/442) -- multi-package support status (MEDIUM confidence)
- [Wrangler bundling docs](https://developers.cloudflare.com/workers/wrangler/bundling/) -- no_bundle flag (HIGH confidence)
- [Wrangler custom builds docs](https://developers.cloudflare.com/workers/wrangler/custom-builds/) -- build command config (HIGH confidence)
- [Wrangler configuration reference](https://developers.cloudflare.com/workers/wrangler/configuration/) -- wrangler.toml fields (HIGH confidence)
- [Wrangler v3 to v4 migration](https://developers.cloudflare.com/workers/wrangler/migration/update-v3-to-v4/) -- breaking changes (HIGH confidence)
- [cloudflare/wrangler-action](https://github.com/cloudflare/wrangler-action) -- CI deployment (HIGH confidence)
- [odoc on opam](https://opam.ocaml.org/packages/odoc/) -- version 3.1.0 latest (HIGH confidence)
- [odoc 3 announcement (Tarides)](https://tarides.com/blog/2026-01-29-ocaml-org-now-uses-odoc-3-what-s-new/) -- features, dune integration (HIGH confidence)
- [2025 documentation best practices (OCaml Discuss)](https://discuss.ocaml.org/t/2025-documentation-best-practices/17008) -- community consensus (MEDIUM confidence)
- [GitHub Pages deployment actions](https://github.com/actions/deploy-pages) -- v4 requirement (HIGH confidence)
- [Dune opam file generation](https://dune.readthedocs.io/en/stable/howto/opam-file-generation.html) -- multi-package dune-project (HIGH confidence)
- [opam: dune versions](https://opam.ocaml.org/packages/dune/) -- 3.22.0 latest (HIGH confidence)
- [OCaml releases](https://ocaml.org/releases) -- 5.4.0 latest, 5.2 still supported (HIGH confidence)

---

*Stack research: 2026-03-26*
