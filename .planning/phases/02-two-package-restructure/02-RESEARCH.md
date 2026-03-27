# Phase 2: Two-Package Restructure - Research

**Researched:** 2026-03-27
**Domain:** dune multi-package setup, opam metadata, Melange library packaging
**Confidence:** HIGH

## Summary

Phase 2 transforms the single-package `spiceflare` repo into two independent opam packages: `spiceflare` (the consumer-facing Melange bindings) and `spiceflare-codegen` (the generator tool). The core work is restructuring `dune-project` to declare two `(package ...)` stanzas with separate dependency trees, adding `(package ...)` attribution to every installable dune stanza, and populating all opam metadata fields so both generated `.opam` files pass `opam lint` with zero errors.

Dune's `generate_opam_files` feature handles most of the work: project-level fields like `(source (github ...))`, `(license ...)`, `(authors ...)`, and `(maintainers ...)` are shared across packages automatically, while per-package fields like `(synopsis ...)`, `(description ...)`, and `(depends ...)` are specific to each `(package ...)` stanza. The `(source (github owner/repo))` shorthand auto-derives `homepage`, `bug-reports`, and `dev-repo` in the generated opam files.

**Primary recommendation:** Declare two `(package ...)` stanzas in `dune-project` with shared global metadata, add `(package ...)` fields to every dune stanza with `public_name`, and give `cf_workers_bindings` a `public_name` so it is installable under the `spiceflare` package.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PKG-02 | Repo contains two separate opam packages: `spiceflare` (bindings) and `spiceflare-codegen` (generator), with disjoint dependency trees | Dune multi-package stanzas with separate `(depends ...)` per package; `(package ...)` attribution on all installable stanzas |
| PKG-03 | Both opam files have complete metadata: `authors`, `homepage`, `source`, `bug-reports`, `license`, `doc` fields populated | `(source (github ...))` auto-derives homepage/bug-reports/dev-repo; `(license ...)`, `(authors ...)`, `(maintainers ...)` at project level; `(documentation ...)` for doc field |
| PKG-05 | `spiceflare` constrains `ocaml >= 5.4` and `melange >= 6.0.1`; `spiceflare-codegen` constrains `ocaml >= 5.4` | User decision: open-ended `>= 5.4` (no upper bound); per-package `(depends ...)` stanzas |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Tech stack**: OCaml >= 5.2, Node.js >= 18, dune >= 3.16, Melange for generated output
- **Naming**: `spiceflare` opam package = published bindings; `spiceflare-codegen` opam package = generator tool
- **Build system**: Dune 3.21.1 installed, lang `3.18` in dune-project, `(using melange 0.1)`
- **Opam files**: auto-generated from dune-project (`generate_opam_files true`)
- **Code style**: ocamlformat 0.27.0, dune files use 1-space indentation
- **GSD workflow**: All edits through GSD commands

## Standard Stack

### Core (no new dependencies -- this is a structural/metadata change)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| dune | 3.21.1 | Build system, opam file generation | Already installed; `generate_opam_files` is the standard approach |
| opam | 2.5.0 | Package manager, `opam lint` validation | Already installed |

No new libraries are introduced in this phase. The work is purely restructuring dune-project and dune stanza metadata.

## Architecture Patterns

### Target dune-project Structure

The dune-project file transforms from a single `(package ...)` to two, with shared global metadata.

```scheme
(lang dune 3.18)

(using melange 0.1)

(name spiceflare)

(version 4.20260317.1)

(generate_opam_files true)

(source
 (github punchcard-dev/spiceflare))

(license ISC)

(authors "Paul Engel")

(maintainers "Paul Engel <paul@example.com>")

(documentation "https://punchcard-dev.github.io/spiceflare/")

(package
 (name spiceflare)
 (synopsis
  "Melange bindings for the Cloudflare Workers runtime API")
 (description
  "Complete set of Melange OCaml external bindings for the Cloudflare Workers runtime API, auto-generated from @cloudflare/workers-types.")
 (depends
  (ocaml
   (>= 5.4))
  (melange
   (>= 6.0.1))
  (odoc :with-doc)))

(package
 (name spiceflare-codegen)
 (synopsis
  "Code generator for Cloudflare Workers Melange bindings")
 (description
  "Reads a JSON intermediate representation extracted from @cloudflare/workers-types and emits structured .ml files covering the full Workers API surface.")
 (depends
  (ocaml
   (>= 5.4))
  (yojson
   (>= 2.0))
  (alcotest
   (and
    :with-test
    (>= 1.7)))
  (odoc :with-doc)))
```

**Key structural points:**

1. **`(name spiceflare)`** remains at the project level. This is required for `dune subst` (used by dune-release). It should match the "primary" package name, which is the shortest prefix. All package names must share this prefix -- `spiceflare` and `spiceflare-codegen` satisfy this constraint.

2. **`(source (github ...))`** at project level auto-derives three opam fields:
   - `homepage:` -> `https://github.com/punchcard-dev/spiceflare`
   - `bug-reports:` -> `https://github.com/punchcard-dev/spiceflare/issues`
   - `dev-repo:` -> `git+https://github.com/punchcard-dev/spiceflare.git`

3. **`(license ...)`, `(authors ...)`, `(maintainers ...)`** at project level are inherited by all packages. Per-package overrides are possible but not needed here.

4. **`(documentation ...)`** at project level maps to the `doc:` field in opam. This is a separate field from `(source ...)` and is NOT auto-derived.

5. **Per-package `(depends ...)`** gives each package its own dependency tree. `spiceflare` depends on `melange` but NOT `yojson`/`alcotest`. `spiceflare-codegen` depends on `yojson`/`alcotest` but NOT `melange`.

### Dune Stanza Package Attribution

In a multi-package project, every installable stanza (those with `public_name`) must be attributed to a package. Dune infers the package from the first component of the dot-separated `public_name`:

| Stanza | Current | Target | Package |
|--------|---------|--------|---------|
| `lib/dune` library | `(name spiceflare_lib)` (private) | Add `(package spiceflare-codegen)` | spiceflare-codegen |
| `bin/dune` executable | `(public_name spiceflare)` | Change to `(public_name spiceflare-codegen) (package spiceflare-codegen)` | spiceflare-codegen |
| `test/dune` test | `(name test_all)` (private) | Add `(package spiceflare-codegen)` | spiceflare-codegen |
| `output/.../dune` library | `(name cf_workers_bindings)` (private) | Add `(public_name spiceflare) (package spiceflare)` | spiceflare |
| `output/.../dune` melange.emit | `(target test_output)` (private) | Add `(package spiceflare)` | spiceflare |

**Critical details:**

- **`lib/dune` (`spiceflare_lib`)**: This is the codegen library. It has no `public_name` and is private. However, it still needs `(package spiceflare-codegen)` so that `dune build -p spiceflare-codegen` includes it. Without this, dune will not know which package it belongs to in a multi-package project.

- **`bin/dune` (`main`)**: The `public_name` changes from `spiceflare` to `spiceflare-codegen` (user decision). This means the installed binary is named `spiceflare-codegen`. The `(package spiceflare-codegen)` field is inferred from the public_name prefix, but explicit attribution is clearer.

- **`output/cf_workers_bindings/dune`**: Currently has no `public_name`. It MUST get `(public_name spiceflare)` to be installable as part of the `spiceflare` package. The public_name `spiceflare` tells dune it belongs to the `spiceflare` package. The internal `(name cf_workers_bindings)` stays the same for local references.

- **`output/cf_workers_bindings_test/dune`**: The `melange.emit` stanza is not installable (it produces JS files for testing, not an installable library). It needs `(package spiceflare)` attribution so it is included when building the `spiceflare` package. Since `melange.emit` stanzas don't install anything, this just controls which package "owns" it for `-p` filtering.

- **`test/dune`**: Private test stanza. Needs `(package spiceflare-codegen)` so it runs with `dune build -p spiceflare-codegen @runtest`.

### Package-level public_name Convention

Dune requires that a library's `public_name` is either the package name itself or starts with the package name followed by a dot. For the bindings library:

```scheme
;; output/cf_workers_bindings/dune
(library
 (name cf_workers_bindings)
 (public_name spiceflare)
 (modes melange)
 (preprocess
  (pps melange.ppx))
 (libraries melange))
```

Using `(public_name spiceflare)` (matching the package name exactly) is the cleanest option. Consumers will `(libraries spiceflare)` in their dune files to depend on this.

### Anti-Patterns to Avoid

- **Forgetting `(package ...)` on private stanzas in multi-package repos**: Without explicit `(package ...)`, dune may not include private libraries/tests in `dune build -p <pkg>`. Always add `(package ...)` to every stanza in a multi-package project.
- **Using `(name)` instead of `(public_name)` for the bindings library**: Only `public_name` makes a library installable. The `cf_workers_bindings` library currently lacks `public_name` and would not be included in the opam package install.
- **Putting codegen deps in the bindings package**: `yojson` and `alcotest` must NOT appear in `spiceflare.opam` -- only in `spiceflare-codegen.opam`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| opam file generation | Manual `.opam` files | `(generate_opam_files true)` in dune-project | Dune auto-generates both `.opam` files from the single source of truth |
| homepage/bug-reports/dev-repo | Manual URLs in each package | `(source (github owner/repo))` | Auto-derives all three fields correctly |
| Package attribution | Guessing which stanza belongs to which package | Explicit `(package ...)` field on every stanza | Prevents build failures with `dune build -p` |

## Common Pitfalls

### Pitfall 1: opam lint Error E23 -- Missing maintainer
**What goes wrong:** `opam lint` fails with an error (not just warning) if `maintainer` is missing.
**Why it happens:** `maintainer` is the only truly mandatory metadata field in opam. Dune's `(maintainers ...)` maps to this.
**How to avoid:** Add `(maintainers "Name <email>")` at the project level in dune-project.
**Warning signs:** `opam lint` returns exit code 1 with "error 23: Missing field 'maintainer'".

### Pitfall 2: Warnings vs Errors in opam lint
**What goes wrong:** Confusing warnings (W) with errors (E). The success criteria says "no errors" -- warnings may be acceptable.
**Why it happens:** opam lint has both error codes (E-prefixed, exit code 1) and warning codes (W-prefixed, exit code 0). Missing `authors` is W25, missing `homepage` is W35, missing `license` is W68 -- all warnings. Missing `maintainer` is E23 -- an error.
**How to avoid:** Populate all fields listed in PKG-03 to get zero warnings AND zero errors. The fields and their lint codes:
  - `maintainer` -> E23 (error if missing)
  - `authors` -> W25 (warning if missing)
  - `homepage` -> W35 (warning if missing) -- auto-derived from `(source (github ...))`
  - `bug-reports` -> W36 (warning if missing) -- auto-derived from `(source (github ...))`
  - `dev-repo` -> W37 (warning if missing) -- auto-derived from `(source (github ...))`
  - `license` -> W68 (warning if missing)
  - `doc` -> no lint check (optional)
**Warning signs:** Run `opam lint spiceflare.opam spiceflare-codegen.opam` after each change.

### Pitfall 3: Private libraries not included in `dune build -p`
**What goes wrong:** `dune build -p spiceflare-codegen` fails because `spiceflare_lib` (a private library) has no package attribution and dune excludes it.
**Why it happens:** With `--only-packages` (what `-p` does internally), dune filters out stanzas not attributed to the specified package. Private libraries without `(package ...)` are excluded.
**How to avoid:** Add `(package spiceflare-codegen)` to `lib/dune` even though it's private.
**Warning signs:** Unresolved dependency errors when building with `-p`.

### Pitfall 4: public_name prefix must match package name
**What goes wrong:** Dune error "public name doesn't start with package name".
**Why it happens:** Dune enforces that `public_name` is either exactly the package name or `<package-name>.<suffix>`.
**How to avoid:** Use `(public_name spiceflare)` for the bindings library (matches package name exactly). Use `(public_name spiceflare-codegen)` for the executable (matches its package name exactly).
**Warning signs:** Dune refuses to build with a clear error message.

### Pitfall 5: Forgetting to update the `(name)` field semantics
**What goes wrong:** `dune subst` (used by dune-release during release) may not work correctly.
**Why it happens:** The project-level `(name ...)` must match one of the declared packages. It should be the shortest package name prefix.
**How to avoid:** Keep `(name spiceflare)` -- it's already the shortest prefix and matches the bindings package.
**Warning signs:** `dune subst` errors during release workflow.

### Pitfall 6: OCaml version constraint format
**What goes wrong:** Using wrong syntax for open-ended version constraint.
**Why it happens:** The ROADMAP says `>= 5.4 & < 5.5` but the user decision overrides this to open-ended `>= 5.4`.
**How to avoid:** Use `(ocaml (>= 5.4))` in both packages. No upper bound.
**Warning signs:** Double-check against the user decision, not the ROADMAP text.

## Code Examples

### Example 1: Multi-package dune-project (verified from melange-re/melange and tarides/dune-release)

```scheme
;; Source: https://github.com/tarides/dune-release/blob/main/dune-project
;; Source: https://github.com/melange-re/melange/blob/main/dune-project

;; Global metadata -- shared by all packages
(lang dune 3.18)
(using melange 0.1)
(name spiceflare)
(generate_opam_files true)
(source (github punchcard-dev/spiceflare))
(license ISC)
(authors "Paul Engel")
(maintainers "Paul Engel <paul@example.com>")

;; Package 1: bindings
(package
 (name spiceflare)
 (synopsis "Melange bindings for the Cloudflare Workers runtime API")
 (description "...")
 (depends
  (ocaml (>= 5.4))
  (melange (>= 6.0.1))
  (odoc :with-doc)))

;; Package 2: codegen
(package
 (name spiceflare-codegen)
 (synopsis "Code generator for Cloudflare Workers Melange bindings")
 (description "...")
 (depends
  (ocaml (>= 5.4))
  (yojson (>= 2.0))
  (alcotest (and :with-test (>= 1.7)))
  (odoc :with-doc)))
```

### Example 2: Library stanza with public_name and package (for bindings)

```scheme
;; output/cf_workers_bindings/dune
(library
 (name cf_workers_bindings)
 (public_name spiceflare)
 (package spiceflare)
 (modes melange)
 (preprocess
  (pps melange.ppx))
 (libraries melange))
```

Note: when `(public_name spiceflare)` matches the package name exactly, `(package spiceflare)` is technically redundant (dune infers it from the first component of public_name). Including it explicitly is clearer in a multi-package repo.

### Example 3: Executable stanza with renamed public_name (for codegen)

```scheme
;; bin/dune
(executable
 (name main)
 (public_name spiceflare-codegen)
 (package spiceflare-codegen)
 (libraries spiceflare_lib))
```

### Example 4: Private library with package attribution (for codegen lib)

```scheme
;; lib/dune
(library
 (name spiceflare_lib)
 (package spiceflare-codegen)
 (libraries yojson))
```

### Example 5: Test stanza with package attribution

```scheme
;; test/dune
(test
 (name test_all)
 (package spiceflare-codegen)
 (libraries spiceflare_lib alcotest))
```

### Example 6: melange.emit test stanza with package attribution

```scheme
;; output/cf_workers_bindings_test/dune
(melange.emit
 (target test_output)
 (package spiceflare)
 (libraries cf_workers_bindings)
 (preprocess
  (pps melange.ppx)))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `.opam` files | `(generate_opam_files true)` in dune-project | dune 2.0 (2019) | Single source of truth for package metadata |
| `(source (uri ...))` for arbitrary URLs | `(source (github owner/repo))` shorthand | dune 2.0 | Auto-derives homepage, bug-reports, dev-repo |
| `(package ...)` inferred from dir structure | Explicit `(package ...)` on stanzas | dune 3.x convention | Required in multi-package repos for clarity |

**Deprecated/outdated:**
- None relevant to this phase

## Open Questions

1. **GitHub org/repo name**
   - What we know: The repo is at `punchcard-dev/spiceflare` or similar on GitHub
   - What's unclear: The exact GitHub username/org for the `(source (github ...))` field
   - Recommendation: Use the actual GitHub URL; planner should parameterize with `<GITHUB_ORG>/<GITHUB_REPO>` if unknown

2. **Author/maintainer details**
   - What we know: User is "Paul" (from memory), familiar with opam ecosystem
   - What's unclear: Full name and email for `(authors ...)` and `(maintainers ...)`
   - Recommendation: Planner should prompt for these values or use placeholders

3. **License choice**
   - What we know: No license currently in dune-project
   - What's unclear: Which SPDX license identifier to use
   - Recommendation: Planner should prompt; ISC, MIT, and Apache-2.0 are common in the OCaml ecosystem

4. **Documentation URL**
   - What we know: PKG-03 requires a `doc` field; `(documentation ...)` in dune-project maps to `doc:` in opam
   - What's unclear: Whether GitHub Pages is set up yet (that's Phase 4)
   - Recommendation: Use `https://<org>.github.io/spiceflare/` as a placeholder -- it won't cause opam lint failures and can be updated later

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| dune | Build system | Yes | 3.21.1 | -- |
| opam | Package management, `opam lint` | Yes | 2.5.0 | -- |
| ocamlformat | Code formatting | Yes | 0.27.0 | -- |

**Missing dependencies:** None. This phase requires only dune and opam, both already installed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | alcotest 1.9.1 |
| Config file | `test/dune` |
| Quick run command | `dune build -p spiceflare-codegen @runtest` |
| Full suite command | `dune build -p spiceflare && dune build -p spiceflare-codegen @runtest` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PKG-02 | `spiceflare` builds independently (no codegen deps) | smoke | `dune build -p spiceflare` | N/A (CLI command) |
| PKG-02 | `spiceflare-codegen` builds independently | smoke | `dune build -p spiceflare-codegen` | N/A (CLI command) |
| PKG-03 | Both opam files pass lint with no errors | smoke | `opam lint spiceflare.opam && opam lint spiceflare-codegen.opam` | N/A (CLI command) |
| PKG-05 | `spiceflare` declares correct version constraints | manual inspection | `grep -A5 "ocaml" spiceflare.opam && grep -A5 "melange" spiceflare.opam` | N/A |
| PKG-05 | `spiceflare-codegen` declares correct version constraints | manual inspection | `grep -A3 "ocaml" spiceflare-codegen.opam` | N/A |

### Sampling Rate
- **Per task commit:** `dune build -p spiceflare && dune build -p spiceflare-codegen && opam lint spiceflare.opam && opam lint spiceflare-codegen.opam`
- **Per wave merge:** Full build + lint check for both packages
- **Phase gate:** Both packages build independently, both opam files pass lint with zero errors AND zero warnings

### Wave 0 Gaps
None -- this phase has no new test files to create. Validation is entirely via `dune build -p` and `opam lint` commands on the restructured project.

## Sources

### Primary (HIGH confidence)
- opam lint manpage (https://opam.ocaml.org/doc/man/opam-lint.html) -- complete list of error/warning codes, field requirements
- dune-release dune-project (https://github.com/tarides/dune-release/blob/main/dune-project) -- verified multi-package structure with `(source (github ...))`
- dune-release generated opam (https://github.com/tarides/dune-release/blob/main/dune-release.opam) -- confirmed auto-derived fields from `(source (github ...))`
- melange dune-project (https://github.com/melange-re/melange/blob/main/dune-project) -- verified OCaml version constraint syntax `(ocaml (and (>= "5.4") (< "5.5")))`
- melange-fetch dune-project and library dune (https://github.com/melange-community/melange-fetch) -- verified Melange library public_name pattern
- Local opam lint output -- ran `opam lint spiceflare.opam` to identify current errors: E23 (missing maintainer), W25 (missing authors), W35 (missing homepage), W36 (missing bug-reports), W68 (missing license)

### Secondary (MEDIUM confidence)
- Dune documentation search results (dune.readthedocs.io, multiple pages) -- package stanza syntax, `(source ...)` shorthand, generate_opam_files, package attribution
- opam-repository PR checks wiki (https://github.com/ocaml/opam-repository/wiki/PR-checks) -- mandatory lint checks for repository submission

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new libraries, just dune/opam configuration
- Architecture: HIGH -- verified against multiple real-world OCaml multi-package projects (dune, melange, dune-release, sihl)
- Pitfalls: HIGH -- confirmed opam lint error/warning codes against official manpage and local testing

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (stable -- dune-project syntax and opam lint checks change rarely)
