# Project Research Summary

**Project:** spiceflare
**Domain:** OCaml/Melange auto-generated bindings library (Cloudflare Workers), opam packaging
**Researched:** 2026-03-26
**Confidence:** HIGH

## Executive Summary

spiceflare is a two-package monorepo: a code generator (`spiceflare-codegen`) that reads a JSON IR extracted from `@cloudflare/workers-types`, and its output (`spiceflare`) -- a publishable opam package of Melange `external` bindings covering the full Cloudflare Workers API surface (~45 modules). The codegen pipeline is complete and working. The remaining work is packaging, testing, documentation, and demo infrastructure -- all well-trodden ground in the Melange ecosystem with clear patterns from `melange-webapi`, `melange-fetch`, `melange-json`, and `gen_js_api`.

The recommended approach is to first fix the compile blockers in the generated bindings (unresolved `ReadableStream`/`WritableStream` types, commented-out dune stanza), then restructure the repo into two opam packages with proper metadata, add a Melange compile-checking test suite, and build out CI, docs, and a demo worker. The stack is conventional: OCaml 5.4 with Melange 6.0.1-54, dune >= 3.18, odoc 3.1 for API docs, wrangler 4.x for the demo worker, and dune-release 2.2 for opam publishing.

The primary risks are: (1) the bindings do not currently compile under Melange -- this must be fixed before anything else proceeds; (2) the OCaml version constraint in the published `spiceflare` package must be permissive enough to accommodate Melange users on different OCaml minor versions (4.14, 5.1, 5.2, 5.3, 5.4); and (3) dune-release has a known quirk with multi-package repos (issue #442) that requires workarounds. All three are well-understood and have documented mitigations.

## Recommended Stack

**Core technologies:**

| Technology | Version | Purpose | Confidence |
|---|---|---|---|
| OCaml | 5.4.x (dev); `>= 4.14` in spiceflare opam depends | Compiler for codegen + development | HIGH |
| Melange | 6.0.1-54 (dev); `>= 4.0.0` in spiceflare opam depends | OCaml-to-JS compiler for bindings | HIGH |
| Dune | >= 3.18 (build); `lang 3.16` in dune-project | Build system with Melange plugin | HIGH |
| odoc | 3.1.0 | API reference generation | HIGH |
| dune-release | 2.2.0 | Tag-to-opam-PR release automation | HIGH |
| wrangler | 4.x | Cloudflare Workers CLI for demo | HIGH |
| alcotest | >= 1.7 | Codegen unit tests | HIGH |

**Key version constraint insight:** The `spiceflare` bindings package must set `(ocaml (>= 4.14))` -- NOT `(>= 5.2)` -- because the bindings are pure `external` declarations that work on any OCaml version Melange supports. Setting `>= 5.2` would exclude the majority of Melange users (those on the `-414`, `-51`, and `-53` variants). The `spiceflare-codegen` package can keep `(ocaml (>= 5.2))` if it uses 5.x-specific features.

See: `.planning/research/STACK.md` for full details including configuration snippets.

## OCaml 5.4 Compatibility

**Melange 6 does support OCaml 5.4.** The variant `melange.6.0.1-54` exists in the opam repository with the constraint `ocaml >= 5.4 & < 5.5`. This was verified directly against the opam package metadata.

**Available Melange 6 variants:**

| Variant | OCaml Constraint |
|---|---|
| `melange.6.0.1-414` | `>= 4.14 & < 4.15` |
| `melange.6.0.1-51` | `>= 5.1 & < 5.2` |
| `melange.6.0.1-52` | `>= 5.2 & < 5.3` |
| `melange.6.0.1-53` | `>= 5.3 & < 5.4` |
| `melange.6.0.1-54` | `>= 5.4 & < 5.5` |

**Implications for the project:**

1. **Development switch:** Use OCaml 5.4.x with `melange.6.0.1-54` for local development.
2. **CI compiler:** Set `ocaml-compiler: 5.4.x` in `setup-ocaml` (update from the current 5.2.x).
3. **Published package constraint:** The `spiceflare` opam package should declare `(ocaml (>= 4.14))` and `(melange (>= 4.0.0))` -- this allows the opam solver to pick the appropriate Melange variant for any user's OCaml version. Do NOT pin to `>= 5.4` in the published package.
4. **The `-54` suffix resolves automatically:** When a user on OCaml 5.4 runs `opam install spiceflare`, the solver picks `melange.6.0.1-54` automatically based on their OCaml version. The bindings package does not need to know about the suffix.

**STACK.md correction:** The STACK.md research recommended OCaml 5.2.x, citing "Melange 6.0.1-52 targets exactly `>=5.2 & <5.3`" and "upgrading to 5.3/5.4 gains nothing." This is factually correct about the `-52` variant but misses the existence of the `-54` variant. Since the user targets OCaml 5.4, the correct development configuration is `ocaml.5.4.x` + `melange.6.0.1-54`. All other tooling (dune, odoc, dune-release, ocamlformat) works identically on 5.4.

**No risk here.** OCaml 5.4 + Melange 6 is a fully supported, released combination.

## Critical Path

The dependency graph dictates a strict ordering for the first three phases:

```
Fix compile blockers (ReadableStream/WritableStream, empty records)
    |
    v
Activate dune library stanza + add (using melange 0.1)
    |
    +---> Compile-checking test suite
    +---> Demo CF Worker
    +---> odoc generation
    |
    v
Two-package restructure + opam metadata
    |
    v
CHANGES.md + release automation
    |
    v
opam publish
```

Nothing downstream can proceed until the bindings compile under Melange. This is the single hardest gate.

## Table Stakes (Must Ship)

From FEATURES.md -- features without which the package will not be adopted:

1. **Bindings compile under Melange** -- the #1 blocker; requires fixing stream type references and activating the dune stanza
2. **opam package with correct metadata** -- source, homepage, bug_reports, authors, maintainers, license, melange version constraint
3. **`(modes melange)` library stanza with `public_name`** -- standard pattern; currently commented out entirely
4. **Two separate opam packages** -- consumers depend on `spiceflare` (bindings) without pulling in codegen dependencies
5. **Melange version constraint in depends** -- `(melange (>= 4.0.0))` to prevent cryptic build failures
6. **README with installation + usage** -- opam install, dune config, minimal code example
7. **CHANGES.md** -- required by dune-release; format: `## version` then bullet list
8. **CI that builds bindings under Melange** -- not just the codegen; must verify the published artifact compiles
9. **Versioning tied to upstream API** -- already done: `4.20260317.1` scheme

See: `.planning/research/FEATURES.md` for the full feature landscape and dependency graph.

## Key Risks

### Risk 1: Bindings do not compile (CRITICAL)

The generated bindings have unresolved `ReadableStream`/`WritableStream` type references and 96 empty record types (`type t = { }`) in the AI module. The dune library stanza is commented out. Nothing works until these are fixed.

**Mitigation:** Fix type resolution in the codegen, emit abstract types for zero-field interfaces, uncomment and configure the dune stanza. Gate all downstream work on `dune build -p spiceflare` succeeding.

### Risk 2: OCaml version constraint excludes most Melange users (CRITICAL)

The current `(ocaml (>= 5.2))` constraint would prevent installation for Melange users on OCaml 4.14, 5.1, 5.3, or 5.4. This is the most common failure mode for first-time opam publishers of Melange libraries.

**Mitigation:** Set `(ocaml (>= 4.14))` on the `spiceflare` bindings package. The codegen package can keep a tighter constraint.

### Risk 3: dune-release multi-package quirk (MODERATE)

dune-release may pick the wrong synopsis for the GitHub release when two opam packages exist (issue #442). The `--pkg-name` flag or `dune-release-action` with explicit `packages` parameter mitigates this.

**Mitigation:** Use `dune-release --pkg-name spiceflare` or the action's `packages` parameter. Test with `--dry-run` before the first real release.

### Risk 4: Demo worker bundling conflicts (MODERATE)

Wrangler's internal esbuild may double-bundle Melange's ES6 output, causing runtime crashes. Melange emits per-module JS files that Wrangler does not expect.

**Mitigation:** Use `no_bundle = true` in `wrangler.toml`. Handle bundling explicitly with esbuild if needed. Test with `wrangler dev --local`.

### Risk 5: odoc fails on generated code (LOW)

Generated doc comments may contain malformed odoc markup from TypeScript JSDoc passthrough (unescaped `{` or `}` characters).

**Mitigation:** Sanitize doc comments during codegen. Run `dune build @doc` in CI.

## Phase Recommendations

### Phase 1: Compile Blockers and Library Activation

**Rationale:** Everything depends on the bindings compiling. This is the critical path gate. No packaging, testing, docs, or demo work can proceed without it.

**Delivers:** A working `dune build` that type-checks all ~45 generated binding modules under Melange.

**Work:**
- Fix `ReadableStream`/`WritableStream` type qualification in codegen
- Fix empty record types (`type t = { }` -> `type t`) in codegen
- Add `(using melange 0.1)` to dune-project
- Activate library stanza: `(library (name spiceflare) (public_name spiceflare) (modes melange))`
- Verify `dune build` succeeds with all binding modules

**Avoids:** Pitfall 5 (unresolved type references), Pitfall 9 (commented-out dune stanza), Pitfall 1 (missing melange plugin)

**Research needed:** No -- the patterns are standard and well-documented.

### Phase 2: Repo Restructure and Packaging

**Rationale:** The two-package split is a prerequisite for correct opam metadata and for publishing. It must happen before any release automation.

**Delivers:** Two opam packages (`spiceflare`, `spiceflare-codegen`) with correct metadata, proper dependency isolation, and the `packages/` directory structure.

**Work:**
- Create `packages/spiceflare/src/` and `packages/spiceflare-codegen/{lib,bin,test}/`
- Move files per the migration table in ARCHITECTURE.md
- Rename `spiceflare_lib` -> `spiceflare_codegen`, update all internal references
- Add two `(package)` stanzas to dune-project with correct dependencies
- Set `(ocaml (>= 4.14))` on spiceflare, `(ocaml (>= 5.2))` on spiceflare-codegen
- Add `(melange (>= 4.0.0))` to spiceflare depends
- Complete opam metadata: source, homepage, bug_reports, authors, maintainers, license (SPDX: `MIT`)
- Verify `dune build -p spiceflare` and `dune build -p spiceflare-codegen` both succeed independently

**Avoids:** Pitfall 2 (OCaml constraint too narrow), Pitfall 3 (missing melange dependency), Pitfall 4 (missing metadata), Pitfall 11 (SPDX license)

**Research needed:** No -- multi-package dune repos are well-documented, and `melange-json` provides a direct precedent.

### Phase 3: Testing and CI

**Rationale:** Testing must precede publishing. The compile-checking test suite is the single most impactful differentiator (auto-generated, 100% surface coverage). CI must verify both packages independently.

**Delivers:** Codegen-emitted compile-checking test suite, updated CI workflows, confidence that the package works.

**Work:**
- Implement codegen-emitted test file per module (`let _ = fn(args)` pattern from melange-webapi)
- Add `(melange.emit (target test_output) (libraries spiceflare))` test stanza
- Extend CI to build bindings under Melange (not just codegen)
- Consider separate CI jobs: `build-codegen` (no Melange), `build-bindings` (needs Melange), `build-all`
- Update CI to use `ocaml-compiler: 5.4.x`
- Optionally add snapshot tests for codegen output stability (dune `(diff ...)` rules)

**Avoids:** Pitfall 17 (no Melange compile-check tests), Pitfall 8 (wrong lower-bound constraints)

**Research needed:** Minimal -- the melange-webapi test pattern is well-documented.

### Phase 4: Documentation

**Rationale:** Docs can proceed in parallel with Phase 3 but are listed after because they benefit from the compile-checking test suite being in place (proves the examples work).

**Delivers:** README with installation/usage, odoc API reference, CHANGES.md, developer docs.

**Work:**
- README: what it is, `opam install spiceflare`, dune config, code examples (pipe-operator convention)
- CHANGES.md with correct format for dune-release (`## 4.20260317.1` heading)
- odoc: verify `dune build @doc` works, add `index.mld` package page
- Sanitize generated doc comments for odoc compatibility
- Expand DEVELOP.md for contributors
- Per-module usage snippets for the most common Workers patterns (KV, D1, R2, fetch)

**Avoids:** Pitfall 15 (odoc failures on generated code), Pitfall 6 (CHANGES.md format mismatch)

**Research needed:** No -- odoc 3.1 and GitHub Pages deployment are standard.

### Phase 5: Demo Worker

**Rationale:** The demo proves the bindings work end-to-end but is not required for the initial opam publish. It is a differentiator, not table stakes.

**Delivers:** A deployable Cloudflare Worker that exercises KV, D1, R2, fetch, and env bindings.

**Work:**
- Create `demo/` directory with `wrangler.toml`, `worker.js` shim, OCaml handler module
- Configure `no_bundle = true` and `[build].command` for dune integration
- Add `package.json` with wrangler dependency
- Verify `wrangler dev --local` works
- Add CI deployment workflow (optional, requires CF account)

**Avoids:** Pitfall 10 (double-bundling), Pitfall 16 (undeclared npm deps)

**Research needed:** MEDIUM -- the Melange + Wrangler integration is non-standard. The `no_bundle` approach is documented but not commonly tested with Melange output. May need experimentation.

### Phase 6: Release Automation and opam Publish

**Rationale:** This is the final step. Everything must be in place: packages, tests, docs, metadata.

**Delivers:** First opam-repository submission, GitHub Releases workflow, automated subsequent releases.

**Work:**
- Run `opam lint` and `dune-release lint` -- fix all warnings
- Test with `dune-release tag --dry-run` and `dune-release publish --dry-run`
- Set up `release.yml` GitHub Actions workflow (tag push -> dune-release -> opam PR)
- Test dune-release-action; fall back to manual `dune-release` commands if unreliable
- Submit first release to opam-repository
- Verify both packages install cleanly from opam in a fresh switch

**Avoids:** Pitfall 6 (tag format mismatch), Pitfall 7 (multi-package synopsis bug), Pitfall 12 (dune subst failures)

**Research needed:** LOW -- dune-release is well-documented. The dune-release-action is newer and less proven (MEDIUM confidence in STACK.md), but the fallback is manual commands.

### Phase Ordering Rationale

- Phases 1-2 are strictly sequential: compilation must work before restructuring can be validated
- Phase 3 (testing) depends on Phase 2 (packages exist to test against)
- Phase 4 (docs) can overlap with Phase 3 but is easier after tests exist
- Phase 5 (demo) can be done anytime after Phase 1 but is deferred because it is a differentiator, not table stakes
- Phase 6 (release) is the final gate and depends on everything else

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 5 (Demo Worker):** The Melange + Wrangler integration path is non-standard. The `no_bundle` + esbuild pattern needs validation. Research the exact JS import paths from Melange output and how they interact with Wrangler's module resolution.

**Phases with standard, well-documented patterns (skip deep research):**
- **Phase 1 (Compile Blockers):** Straightforward codegen fixes and dune configuration
- **Phase 2 (Restructure):** Direct precedent in melange-json, melange-webapi
- **Phase 3 (Testing):** melange-webapi's ~50 test files provide the exact pattern
- **Phase 4 (Documentation):** odoc 3.1 + GitHub Pages is well-trodden
- **Phase 6 (Release):** dune-release 2.2 is mature; opam publishing is well-documented

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified against opam package metadata, Melange docs, dune docs. OCaml 5.4 + Melange 6.0.1-54 confirmed available. |
| Features | HIGH | Based on direct inspection of melange-community repos (melange-fetch, melange-webapi, melange-json, gen_js_api). Clear ecosystem norms. |
| Architecture | HIGH | Multi-package dune workspace is a standard pattern. melange-json provides direct precedent. Component boundaries are clean. |
| Pitfalls | HIGH | 17 pitfalls identified from opam packaging guides, dune-release docs, and direct codebase inspection. Critical ones are actionable. |

**Overall confidence:** HIGH

### Gaps to Address

- **`melange.ppx` requirement:** STACK.md says `(preprocess (pps melange.ppx))` is required for `[@mel.obj]`, `[@mel.send]`, etc. ARCHITECTURE.md and FEATURES.md say it is NOT needed because the Melange compiler handles `[@@mel.*]` attributes directly. This contradiction must be resolved during Phase 1 by testing with and without the PPX. The ARCHITECTURE.md position (no PPX needed for pure `external` declarations) is more likely correct based on melange-webapi precedent.
- **Melange version lower bound:** STACK.md suggests `(melange (>= 6.0))`. ARCHITECTURE.md suggests `(melange (>= 4.0.0))`. PITFALLS.md warns about testing lower bounds. The correct approach: determine the oldest Melange version that supports all `[@mel.*]` attributes used in the generated output, and test against it. `>= 4.0.0` is a safe starting point; tighten if needed.
- **dune-release-action reliability:** Described as "half vibe-coded" in its own announcement. The fallback (manual `dune-release` commands) is documented in STACK.md and should be the primary plan, with the action as a convenience.
- **Numeric overload suffixes:** `get_2`, `put_2` etc. are a known UX issue. Fixing these in the codegen is desirable before v1 but could be documented as a known limitation if time-constrained.

## Sources

### Primary (HIGH confidence)
- opam package metadata for `melange.6.0.1-54`, `melange.6.0.1-52`, `melange.6.0.1-51` -- version constraints verified directly
- [melange-webapi](https://github.com/melange-community/melange-webapi) -- published Melange bindings library, test patterns
- [melange-fetch](https://github.com/melange-community/melange-fetch) -- README pattern, CI workflow, CHANGES.md format
- [melange-json](https://github.com/melange-community/melange-json) -- multi-package dune-project precedent
- [Melange build system docs](https://melange.re/v2.0.0/build-system/) -- dune plugin config, library stanzas
- [Dune opam file generation](https://dune.readthedocs.io/en/stable/howto/opam-file-generation.html) -- multi-package setup
- [opam Packaging Guide](https://opam.ocaml.org/doc/Packaging.html) -- metadata requirements, publishing workflow
- [Cloudflare Workers wrangler docs](https://developers.cloudflare.com/workers/wrangler/) -- no_bundle, custom builds, configuration

### Secondary (MEDIUM confidence)
- [dune-release-action](https://github.com/davesnx/dune-release-action) -- GitHub Actions automation (newer, less proven)
- [dune-release multi-package issue #442](https://github.com/tarides/dune-release/issues/442) -- known synopsis bug
- [Melange package management docs](https://melange.re/unstable/package-management.html) -- opam publishing patterns
- [Dune universal libraries preview](https://melange.re/blog/posts/dune-universal-libraries-preview) -- experimental, not needed

### Tertiary (LOW confidence)
- None -- all research areas had multiple corroborating sources

---
*Research completed: 2026-03-26*
*Ready for roadmap: yes*
