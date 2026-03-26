# Domain Pitfalls

**Domain:** OCaml/Melange bindings library publishing (opam)
**Project:** spiceflare
**Researched:** 2026-03-26

---

## Critical Pitfalls

Mistakes that cause opam-repo PR rejection, broken installs, or user-facing compile failures.

---

### Pitfall 1: Missing `(using melange 0.1)` in dune-project

**What goes wrong:** The bindings package ships with `(modes melange)` in its library dune file but omits `(using melange 0.1)` from its own `dune-project`. When opam CI builds the package with `dune build -p spiceflare`, dune does not recognize the `melange` mode and the build fails. The package never reaches the opam repository.

**Why it happens:** The current `dune-project` has `(lang dune 3.16)` and no `(using melange ...)` directive. The codegen tool itself is pure OCaml and does not need Melange, so the directive was never added. But the *bindings* package requires it.

**Consequences:** opam-repo CI build failure. PR rejected.

**Prevention:**
- The bindings package (`spiceflare`) must have `(using melange 0.1)` in the dune-project that governs it. If using a monorepo with two packages, the bindings' dune-project (or the shared one) must include this directive.
- The codegen package (`spiceflare-codegen`) does NOT need it -- it produces `.ml` files but does not compile them with Melange.
- Splitting into two dune-project files (one per package) is the cleanest approach when one package needs Melange and the other does not.

**Detection:** Run `opam install . --with-test` locally in a fresh switch. If the bindings' `(modes melange)` stanza is present but `(using melange 0.1)` is absent, dune will error immediately.

**Phase:** Packaging / repo restructuring phase.

**Confidence:** HIGH -- verified against melange-webapi's dune-project (uses `(lang dune 3.18)` + `(using melange 0.1)`) and Melange official docs.

---

### Pitfall 2: OCaml version constraint too narrow for Melange users

**What goes wrong:** The current `dune-project` requires `(ocaml (>= 5.2))`. Melange 6 (latest) requires `ocaml >= 5.1.1 & < 5.2` for its `-51` variant, and `ocaml >= 4.14 & < 4.15` for its `-414` variant. Melange 5 supports 4.14, 5.1, 5.2, and 5.3. Setting `>= 5.2` excludes Melange 6 users on the `-51` variant and all `4.14` users entirely. This dramatically limits the installable audience.

**Why it happens:** The codegen tool (which uses OCaml 5.x features) and the bindings library (which is pure `external` declarations) share a single `dune-project` with a single OCaml constraint. The bindings themselves use no OCaml 5.x features -- they are `external` declarations and type definitions that work on OCaml 4.14+.

**Consequences:** Users on Melange 6 (`-51` variant) cannot install the bindings because the solver sees `ocaml >= 5.2` conflicting with `ocaml >= 5.1.1 & < 5.2`. This is the most common Melange configuration. The package is installable by almost nobody.

**Prevention:**
- The bindings package should have a permissive OCaml lower bound: `(ocaml (>= 4.14))` to match what Melange itself supports.
- The codegen package can keep `(ocaml (>= 5.2))` if it genuinely uses 5.x-specific features.
- This is another strong argument for two separate dune-project files / two packages in the monorepo.

**Detection:** Try `opam install spiceflare` in a switch with `ocaml.5.1.1` + `melange.6.0.1-51`. If the solver says "no solution," the constraint is wrong.

**Phase:** Packaging phase -- must be resolved before first opam-repo submission.

**Confidence:** HIGH -- verified against Melange opam package metadata (melange.6.0.1-51 requires ocaml `>= 5.1.1 & < 5.2`; melange.6.0.1-414 requires ocaml `>= 4.14 & < 4.15`).

---

### Pitfall 3: Missing `melange` runtime dependency in opam metadata

**What goes wrong:** The bindings package `spiceflare.opam` does not declare a dependency on `melange`. When a user runs `opam install spiceflare`, opam does not pull in Melange. The user then tries `dune build` and gets an error about the `melange` mode being unknown or the Melange compiler being absent.

**Why it happens:** The current opam metadata was written for the codegen tool, which does not need Melange. The bindings package is not yet separated and has no Melange dependency.

**Consequences:** Broken user experience. The package installs but nothing works.

**Prevention:**
- The bindings opam file must include `"melange" {>= "5.0.0"}` (or whatever the minimum compatible version is) in its `depends` field.
- Use a version range that matches the `@mel.*` attributes used in the generated code. If the code uses `@mel.this` (which it does), this requires Melange >= 3.0. If it uses discriminated unions (`@mel.tag`), that requires Melange >= 5.0.
- Pin to the minimum Melange version that supports all attributes used in generated output.

**Detection:** `opam lint` will not catch this -- it only checks syntax, not semantic correctness of dependencies. You must test with `opam install spiceflare` in a clean switch and verify `dune build` works.

**Phase:** Packaging phase.

**Confidence:** HIGH -- standard requirement for all published Melange libraries (verified against melange-webapi, melange-fetch opam files).

---

### Pitfall 4: opam metadata missing homepage, bug-reports, dev-repo, license

**What goes wrong:** The current `dune-project` package stanza has `name`, `synopsis`, `description`, and `depends` but is missing `homepage`, `bug-reports`, `dev-repo`, `license`, `authors`, and `maintainers`. `opam lint` produces warnings for each missing field. `dune-release lint` refuses to proceed. The opam-repo CI flags the submission.

**Why it happens:** The opam file was initially generated as a skeleton and never filled in.

**Consequences:** `dune-release` refuses to run. Manual submission to opam-repo gets lint warnings that reviewers will require fixing before merge.

**Prevention:** Add all recommended metadata fields to the `(package ...)` stanza in `dune-project`:
```
(license MIT)
(authors "...")
(maintainers "...")
(homepage "https://github.com/...")
(bug_reports "https://github.com/.../issues")
(source (github .../...))
```

**Detection:** Run `opam lint spiceflare.opam` locally. Any warning above 0 indicates missing fields.

**Phase:** Packaging phase -- straightforward to fix.

**Confidence:** HIGH -- opam packaging guide and opam-repo PR checks wiki confirm these fields are checked.

---

### Pitfall 5: Generated bindings have unresolved type references

**What goes wrong:** Users install the bindings, add `cf_workers_bindings` to their `(libraries ...)`, and get compile errors: `Unbound type constructor readable_stream` (and `writable_stream`). The generated code references bare type names that are never defined at the top level of any module.

**Why it happens:** The codegen emits `Tname "readable_stream"` and `Tname "writable_stream"` as hardcoded bare names (documented in CONCERNS.md). These should be qualified as `Streams.Readable_Stream.t` or similar. The codegen also currently has `Partial<T>` erased, intersection types truncated, and `Iterable<T>` mapped to `T array` -- none of which cause compile errors but all produce incorrect types.

**Consequences:** Users cannot compile any code that touches streaming APIs (images, R2 object bodies, etc.). This is a large portion of the Workers API surface. The package appears broken.

**Prevention:**
- Fix the `ReadableStream` / `WritableStream` resolution before publishing. This is documented in CONCERNS.md and is a known critical issue.
- Implement a CI step that compiles the generated bindings with Melange before any release. If the bindings do not compile, the release is blocked.
- The codegen-emitted compile-checking test suite (from PROJECT.md Active items) is the long-term fix.

**Detection:** Run `dune build` on the bindings directory with Melange enabled. Any unbound type constructor is caught immediately. This must be a CI gate.

**Phase:** Pre-packaging -- the compile-blocker fixes must happen before the packaging phase.

**Confidence:** HIGH -- directly verified from CONCERNS.md and code inspection.

---

### Pitfall 6: dune-release tag format mismatch with version in CHANGES.md

**What goes wrong:** `dune-release tag` creates a git tag by parsing the first version entry in `CHANGES.md`. If the version format in the changelog does not match what dune-release expects, or if there is no `CHANGES.md` file at all, the release process fails silently or creates an unexpected tag.

**Why it happens:** The project currently has no `CHANGES.md` file. The version in `dune-project` is `4.20260317.1` (derived from the Cloudflare workers-types version). dune-release expects to find the version in the changelog and uses it to create an annotated tag. If the changelog says `## 4.20260317.1` but the tag format differs from what opam-repo expects, the submission fails.

**Consequences:** Release automation breaks. Tags are created with wrong names. The tarball URL in the opam file points to a non-existent GitHub release.

**Prevention:**
- Create a `CHANGES.md` with the correct format: `## <version>` as the first heading, where `<version>` matches the `(version ...)` in `dune-project`.
- Use annotated tags (dune-release creates these by default, but manual `git tag` without `-a` will break things).
- Decide on a versioning scheme early. The current scheme (`4.20260317.1` tracking the CF workers-types version) is unusual for opam but valid. Make sure CHANGES.md, dune-project version, and git tags all agree.
- Consider `dune-release-action` (davesnx/dune-release-action) for GitHub Actions automation, which handles tag-to-release-to-opam-PR in one workflow.

**Detection:** Run `dune-release lint` locally before any release. It checks for CHANGES.md presence and format.

**Phase:** Release automation phase.

**Confidence:** HIGH -- dune-release README and OCaml publishing docs confirm the changelog format requirement.

---

## Moderate Pitfalls

---

### Pitfall 7: Two packages in one repo with dune-release picks wrong synopsis

**What goes wrong:** When `dune-release` processes a repository with two `.opam` files (`spiceflare.opam` and `spiceflare-codegen.opam`), it may pick the synopsis from the wrong package for the opam-repo PR title. This is a known issue (tarides/dune-release#442).

**Why it happens:** dune-release does not consistently prioritize the package named in the `(name ...)` field of `dune-project`. It may select metadata from whichever `.opam` file it encounters first.

**Prevention:**
- Use `dune-release-action` with the `packages` parameter to explicitly specify which package to release.
- Alternatively, release packages one at a time using `dune-release --pkg-name spiceflare`.
- Test the release flow in a dry run: `dune-release tag --dry-run` and `dune-release publish --dry-run`.

**Phase:** Release automation phase.

**Confidence:** MEDIUM -- confirmed via the open GitHub issue, but the `--pkg-name` flag may fully mitigate it.

---

### Pitfall 8: Lower-bound dependency constraints are wrong

**What goes wrong:** The opam file declares `(yojson (>= 2.0))` or `(melange (>= 5.0))` but the code actually uses a function introduced in a later minor version. opam-repo CI runs a lower-bounds check that installs the *oldest* allowed version of each dependency. If the package does not compile with `yojson 2.0.0` exactly, the PR is rejected.

**Why it happens:** Developers test with the latest versions locally and guess at lower bounds. The codegen uses yojson, which is stable, so this is lower risk there. But the Melange dependency for the bindings is more dangerous -- `@mel.this` semantics changed between Melange versions, and `@mel.send.pipe` was deprecated in Melange 5.

**Consequences:** opam-repo CI rejection with a cryptic build failure at the lower-bounds check step.

**Prevention:**
- Test locally with the oldest allowed dependency versions. Use `opam install --oldest` or a dedicated lower-bounds CI job (see sim642.eu blog post on this topic).
- For Melange, pin the lower bound to the version you actually test against. Do not guess.
- For the codegen tool: `yojson >= 2.0` is likely correct (the API is stable). `alcotest >= 1.7` should be verified.

**Detection:** Add a CI job that uses `opam-0install --prefer-oldest` or opam's built-in `+count[version-lag,solution]` solver criteria.

**Phase:** Packaging / CI phase.

**Confidence:** HIGH -- opam-repo CI explicitly tests lower bounds, and multiple sources confirm this is a common failure mode.

---

### Pitfall 9: Generated output dune stanza is inactive / commented out

**What goes wrong:** The bindings library's `dune` file at `output/cf_workers_bindings/dune` is entirely commented out. The generated `.ml` files are not buildable. If this stanza is shipped as-is in the opam package, `dune build -p spiceflare` will either skip the library entirely or fail because no library is defined.

**Why it happens:** The dune stanza was commented out during development because no Melange environment was configured in the codegen repo. This was a reasonable development choice but cannot persist into a released package.

**Consequences:** The opam package installs but provides no library. Users add `cf_workers_bindings` to their `(libraries ...)` and get "library not found."

**Prevention:**
- Uncomment and activate the library stanza before packaging.
- Add `(using melange 0.1)` to the dune-project.
- Verify with `dune build -p spiceflare` that the library is built and installed.

**Detection:** `opam install . && dune build` in a consumer project that depends on `spiceflare`. If `cf_workers_bindings` is not found, the stanza is inactive.

**Phase:** Pre-packaging, alongside compile-blocker fixes.

**Confidence:** HIGH -- directly observed in the codebase.

---

### Pitfall 10: Wrangler double-bundles Melange output in demo app

**What goes wrong:** The demo CF Worker uses `wrangler dev` or `wrangler deploy`, which invokes esbuild internally. If the entry point is a `.js` file in `_build/default/...`, Wrangler's bundler re-bundles Melange's already-compiled output, potentially duplicating modules, mangling paths, or pulling in Node.js polyfills. Wrangler v4 upgraded to esbuild 0.24, which changed wildcard import behavior.

**Why it happens:** Melange compiles OCaml to per-module ES6 `.js` files. The design doc prescribes a `worker.js` shim that imports the Melange output and re-exports it. Wrangler then bundles this shim + imports. If the shim's import path is wrong, or if Wrangler's bundler resolves paths differently than expected, things break silently (the worker deploys but crashes at runtime with missing module errors).

**Consequences:** Demo app fails to deploy or crashes at runtime with opaque esbuild / V8 errors. Users trying the demo as a getting-started guide are immediately blocked.

**Prevention:**
- Use `no_bundle = true` in `wrangler.toml` and handle bundling with esbuild separately (as the design doc describes). This gives full control over the bundle step.
- Alternatively, use Wrangler's `[build]` custom build section to run `dune build && esbuild ...` before Wrangler deploys.
- Pin the esbuild version in the demo's package.json to avoid surprise behavior changes.
- Test the demo with `wrangler dev --local` before publishing.

**Detection:** `wrangler dev` should start without errors and the worker should respond to HTTP requests. Any import/module error at runtime means the bundling is wrong.

**Phase:** Demo app phase.

**Confidence:** MEDIUM -- based on CF Workers docs and design doc prescriptions; no direct Melange+Wrangler failure reports found, but the architecture is non-standard enough that issues are likely.

---

### Pitfall 11: License field not SPDX-compliant

**What goes wrong:** opam-repo CI runs a lint check requiring the `license` field to conform to the SPDX standard (e.g., `"MIT"`, `"Apache-2.0"`, `"ISC"`). Non-standard strings like `"PSF-2.0"` or `"BSD"` (without the full SPDX identifier) cause lint errors.

**Why it happens:** The project has a LICENSE file but no `license` field in `dune-project`. When added, it must use the exact SPDX identifier.

**Consequences:** opam-repo PR lint failure.

**Prevention:** Verify the license identifier against the SPDX license list (https://spdx.org/licenses/). Use `"MIT"` not `"mit"` or `"MIT License"`.

**Detection:** `opam lint` checks this.

**Phase:** Packaging phase.

**Confidence:** HIGH -- confirmed by opam-repository issue #21017.

---

### Pitfall 12: `dune subst` fails because version placeholder is missing

**What goes wrong:** opam builds run `dune subst` as the first build step (when `{dev}` is set). This replaces `%%VERSION%%` placeholders in source files with the version from the VCS tag. If the `(version ...)` field in `dune-project` is hardcoded (as it currently is: `4.20260317.1`), `dune subst` still works -- but if the `.opam` file's build section includes `["dune" "subst"] {dev}` (which it does), and the tag does not exist in the distribution tarball, `dune subst` will fail.

**Why it happens:** The current build stanza in the generated opam file includes `["dune" "subst"] {dev}`. This is correct for dev installs (pinned from git) but only works when there is a proper VCS tag. For release tarballs, `dune subst` is not run (the `{dev}` guard prevents it). The real risk is if someone pins the package from git without a proper tag.

**Prevention:**
- Ensure the `(version ...)` in `dune-project` is updated before each release (the CI already does this via `sed`).
- Use `dune-release` which handles version substitution correctly.
- Do not manually edit the opam file's build section; let `(generate_opam_files true)` produce it.

**Detection:** `opam pin add spiceflare .` in a local checkout. If `dune subst` errors, the version setup is wrong.

**Phase:** Release automation phase.

**Confidence:** MEDIUM -- the `{dev}` guard makes this a niche issue, but it is a common source of confusion for first-time opam publishers.

---

## Minor Pitfalls

---

### Pitfall 13: Numeric overload suffixes confuse users

**What goes wrong:** Users see `get_2`, `put_2`, `append_2` in the bindings and have no idea which overload to use. They try the wrong one, get a runtime type error in the JS layer, and file a bug report.

**Why it happens:** The codegen falls back to numeric suffixes when it cannot derive purpose-based names. This is documented in CONCERNS.md.

**Prevention:**
- Implement purpose-based suffix generation before publishing (design doc describes this).
- At minimum, add odoc comments on numeric-suffix bindings explaining what distinguishes each overload (e.g., parameter types accepted).
- Document this limitation prominently in the README.

**Phase:** Codegen improvement (pre-packaging ideally, or documented as known limitation for v1).

**Confidence:** HIGH -- directly observed in generated output.

---

### Pitfall 14: Empty record types (`type t = { }`) in generated output

**What goes wrong:** The AI module has 96 occurrences of `type t = { }`. Empty OCaml records cannot be constructed with `{}` -- users get a confusing error. These types serve no purpose.

**Why it happens:** Zero-property interfaces produce empty record type definitions instead of abstract types.

**Prevention:** Fix the emitter to produce `type t` (abstract) instead of `type t = { }` when there are no fields.

**Detection:** `grep -c 'type t = { }' output/cf_workers_bindings/*.ml`

**Phase:** Codegen improvement -- low effort, high polish.

**Confidence:** HIGH -- directly observed.

---

### Pitfall 15: odoc generation fails on generated bindings

**What goes wrong:** The CI runs `dune build @doc` which invokes odoc on all libraries, including the generated bindings. If the bindings have syntax issues, undocumented module references, or circular dependencies, odoc fails and blocks the release.

**Why it happens:** Generated code is rarely tested against odoc. The `(** ... *)` comments in generated files may contain malformed odoc markup (e.g., unescaped `{` or `}` characters from TypeScript JSDoc passthrough).

**Prevention:**
- Run `dune build @doc` as part of CI (it already is in `ci.yml` -- good).
- Sanitize JSDoc comments during codegen to escape odoc-special characters.
- Add `@inline` or `@canonical` annotations if module aliasing causes odoc confusion.

**Detection:** `dune build @doc` -- any failure is visible immediately.

**Phase:** Documentation phase.

**Confidence:** MEDIUM -- plausible based on common odoc issues with generated code, but not directly verified.

---

### Pitfall 16: Demo app requires npm dependencies not declared in opam

**What goes wrong:** The demo CF Worker needs `wrangler`, `esbuild`, and potentially `@cloudflare/workers-types` (for TypeScript checking of the JS shim) installed via npm. These are not OCaml dependencies and cannot be expressed in opam's `depends` field. Users clone the repo, run `opam install .`, and expect the demo to work -- but it does not because npm packages are missing.

**Why it happens:** The boundary between the opam (OCaml) world and the npm (JS) world is a fundamental tension in Melange projects. The bindings library itself has no npm dependencies (it is pure `external` declarations), but the demo that *uses* the bindings needs JS tooling.

**Prevention:**
- Use opam's `depexts` field for npm dependencies: `depexts: [ ["wrangler"] {npm-version = ">= 3.0.0"} ]` -- but only on the demo package, not the bindings.
- Better: keep the demo in a separate directory with its own `package.json` and document the setup steps clearly.
- Provide a `Makefile` or script that runs both `opam install` and `npm install` for the demo.

**Detection:** Try the demo setup from scratch in a clean environment. Any missing tool will be immediately apparent.

**Phase:** Demo app phase.

**Confidence:** HIGH -- this is a fundamental property of any Melange + JS runtime project.

---

### Pitfall 17: `alcotest` listed as test dep but no compile-check tests exist for bindings

**What goes wrong:** The package claims to have tests (`@runtest`), but the test suite only covers the codegen tool (naming, parsing, emit). There are no tests that verify the generated bindings compile under Melange. A user installs the bindings, encounters a compile error, and the project looks untested.

**Why it happens:** The test suite was written for the codegen, not the output. Testing the output requires a Melange build environment, which the codegen repo did not originally have.

**Prevention:**
- Implement the codegen-emitted compile-checking test suite described in PROJECT.md. This is the single most important quality gate for the bindings package.
- At minimum, add a CI step that runs `dune build` on the bindings with Melange enabled.

**Detection:** Check whether `dune runtest` exercises any Melange compilation. If it only tests OCaml-native code, the bindings are untested.

**Phase:** Testing phase -- must precede first release.

**Confidence:** HIGH -- directly observed in test suite structure.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|---|---|---|
| Repo restructuring (two packages) | OCaml version constraint conflict between codegen and bindings (Pitfall 2) | Separate dune-project files with different OCaml bounds |
| Repo restructuring | Missing `(using melange 0.1)` for bindings (Pitfall 1) | Add to bindings dune-project; verify with `dune build -p spiceflare` |
| Compile-blocker fixes | Unresolved stream types break entire API surface (Pitfall 5) | Fix before any packaging work begins |
| Packaging / opam metadata | Missing metadata fields (Pitfall 4), missing melange dep (Pitfall 3), SPDX license (Pitfall 11) | Run `opam lint` and `dune-release lint` as gates |
| Packaging / opam metadata | Lower-bound constraints wrong for Melange version (Pitfall 8) | Test with `--prefer-oldest` in CI |
| Testing | No Melange compile-check tests (Pitfall 17) | Build the codegen-emitted test suite before release |
| Demo app | Wrangler bundling conflicts (Pitfall 10), npm deps undeclared (Pitfall 16) | Use `no_bundle`, separate package.json, clear setup docs |
| Release automation | CHANGES.md format / tag mismatch (Pitfall 6), dune-release multi-package quirk (Pitfall 7) | Create CHANGES.md early; use `--pkg-name` flag or dune-release-action |
| Documentation | odoc failures on generated code (Pitfall 15), numeric suffixes undocumented (Pitfall 13) | Sanitize comments; document known limitations |

---

## Sources

- [opam Packaging Guide](https://opam.ocaml.org/doc/Packaging.html)
- [opam-repository PR Checks Wiki](https://github.com/ocaml/opam-repository/wiki/PR-checks)
- [opam-repository CI Failure Guide](https://github.com/ocaml/opam-repository/wiki/How-to-deal-with-CI)
- [Melange Build System Docs (v4)](https://melange.re/v4.0.0/build-system.html)
- [Melange Package Management Docs](https://melange.re/unstable/package-management.html)
- [Melange 5 Announcement](https://melange.re/blog/posts/announcing-melange-5)
- [melange 6.0.1-51 opam metadata](https://opam.ocaml.org/packages/melange/melange.6.0.1-51/)
- [melange-webapi GitHub](https://github.com/melange-community/melange-webapi) -- reference Melange bindings library
- [melange-fetch opam page](https://ocaml.org/p/melange-fetch/0.1.0) -- reference Melange bindings library
- [dune-release GitHub](https://github.com/tarides/dune-release)
- [dune-release multi-package issue #442](https://github.com/tarides/dune-release/issues/442)
- [dune-release-action](https://github.com/davesnx/dune-release-action) -- GitHub Actions automation
- [OCaml Publishing Guide](https://ocaml.org/docs/publishing-packages-w-dune)
- [Lower-bounds CI for OCaml packages](https://sim642.eu/blog/2022/03/13/ocaml-dependencies-lower-bounds-ci/)
- [Cloudflare Workers Custom Builds](https://developers.cloudflare.com/workers/wrangler/custom-builds/)
- [dune subst documentation](https://dune.readthedocs.io/en/latest/reference/dune-project/subst.html)
- [opam-repository SPDX license issue #21017](https://github.com/ocaml/opam-repository/issues/21017)
- Project files: `.planning/PROJECT.md`, `.planning/codebase/CONCERNS.md`, `dune-project`, `spiceflare.opam`, `output/cf_workers_bindings/dune`

---

*Pitfalls audit: 2026-03-26*
