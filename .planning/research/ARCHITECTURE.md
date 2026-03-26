# Architecture Patterns

**Domain:** Two-opam-package monorepo for Melange bindings + OCaml codegen tool
**Researched:** 2026-03-26

## Recommended Architecture

### High-Level Layout

The repository becomes a **dune multi-package workspace** with two opam packages sharing a single `dune-project`, a single `(version)`, and a unified CI pipeline. The key structural change: generated `.ml` files move from `output/cf_workers_bindings/` to a package-owned path, and the codegen library/executable get their own package scope.

```
ocaml-spiceflare/                        # workspace root
  dune-project                           # two (package) stanzas, (using melange 0.1)
  spiceflare.opam                        # generated - Melange bindings package
  spiceflare-codegen.opam                # generated - codegen tool package

  packages/
    spiceflare/                          # --- opam package: spiceflare ---
      src/
        dune                             # (library (name spiceflare) (public_name spiceflare) (modes melange))
        *.ml                             # generated binding files (ai.ml, kv.ml, d1.ml, ...)
      test/
        dune                             # (melange.emit (target test_output) (libraries spiceflare))
        test_bindings.ml                 # imports all modules, type-checks under Melange
    spiceflare-codegen/                  # --- opam package: spiceflare-codegen ---
      lib/
        dune                             # (library (name spiceflare_codegen) (public_name spiceflare-codegen.lib) (libraries yojson))
        ir.ml, ir_parse.ml, resolve.ml, naming.ml, transform.ml, binding_ast.ml, emit.ml
      bin/
        dune                             # (executable (name main) (public_name spiceflare-codegen) (package spiceflare-codegen) (libraries spiceflare_codegen))
        main.ml
      test/
        dune                             # (test (name test_all) (package spiceflare-codegen) (libraries spiceflare_codegen alcotest))
        test_all.ml

  data/
    workers-ir.json                      # committed IR artifact (not part of either package)
  extract/                               # TypeScript extraction toolchain (not part of either package)
    extract.ts, grouping.ts, ...
  demo/                                  # deployable CF Worker demo (not part of either package)
    src/
      dune                               # (melange.emit (target worker_output) (libraries spiceflare))
      worker.ml
    worker.js                            # JS entry-point shim
    wrangler.toml
  _notes/                                # design docs
```

### Why This Layout (Not Flat)

**Rationale for `packages/` directory:** Dune resolves package membership through `public_name` prefix matching (a library with `(public_name spiceflare)` belongs to the `spiceflare` package automatically). However, having two packages' source files interleaved at the repo root creates confusion about what belongs where. The `packages/` directory makes boundaries visible in the filesystem, which matters for a project where one package's source files are **generated** by the other package's tool.

**Alternative considered: flat layout.** Keeping `lib/`, `bin/`, `output/` at root with `(package)` fields on each stanza. This works mechanically but obscures the package boundary -- especially problematic because `dune build -p spiceflare` must build the Melange library (which requires `melange` as a dep) while `dune build -p spiceflare-codegen` must build the native OCaml tool (which must NOT require `melange`). Physical separation makes this split visible.

**Alternative considered: two repos.** Rejected. The codegen and bindings share a release cadence (both tied to `@cloudflare/workers-types` version). Monorepo simplifies CI, avoids cross-repo version coordination, and makes the weekly update workflow a single PR.

## Component Boundaries

| Component | Responsibility | Package | Communicates With |
|-----------|---------------|---------|-------------------|
| `spiceflare` library | Melange bindings for CF Workers API | `spiceflare` | Consumers' Melange code |
| `spiceflare` tests | Type-check all bindings under Melange | `spiceflare` | `spiceflare` library |
| `spiceflare_codegen` library | IR parsing, resolution, transform, emission | `spiceflare-codegen` | `workers-ir.json` (reads), `spiceflare` src dir (writes) |
| `spiceflare-codegen` executable | CLI entry point for codegen | `spiceflare-codegen` | `spiceflare_codegen` library |
| `spiceflare-codegen` tests | Unit tests for codegen logic | `spiceflare-codegen` | `spiceflare_codegen` library |
| `extract/` toolchain | TS extraction to JSON IR | neither package | `@cloudflare/workers-types` (reads), `data/workers-ir.json` (writes) |
| `demo/` worker | Deployable example CF Worker | neither package | `spiceflare` library (depends on) |

### Critical Boundary: No Build-Time Dependency Between Packages

The `spiceflare` package (Melange bindings) has **no build dependency** on `spiceflare-codegen`. The generated `.ml` files are committed to git and published as-is. The codegen tool is only needed at development time to regenerate them. This means:

- Consumers install `spiceflare` without ever touching the codegen
- `dune build -p spiceflare` needs only `melange` (no `yojson`, no native OCaml compilation of the codegen)
- `dune build -p spiceflare-codegen` needs only `yojson` (no `melange`)
- The two packages have **disjoint dependency trees**

## Data Flow

### Development-Time Flow (Regeneration)

```
@cloudflare/workers-types (npm)
    |
    v
extract/extract.ts + grouping.ts     [Stage 1: TS -> JSON]
    |
    v
data/workers-ir.json                  [committed artifact]
    |
    v
spiceflare-codegen executable         [Stage 2: JSON -> .ml]
    |
    v
packages/spiceflare/src/*.ml          [committed artifacts, ~43 files, ~10K lines]
    |
    v
dune build (with melange)             [compile-check: type-checks under Melange]
```

### Consumer-Time Flow (Using the Bindings)

```
opam install spiceflare               [installs Melange library]
    |
    v
consumer's dune file:
  (library
   (name my_worker)
   (modes melange)
   (libraries spiceflare))
    |
    v
consumer's melange.emit stanza        [emits JS from OCaml + bindings]
    |
    v
worker.js entry-point shim            [hand-authored, 3 lines]
    |
    v
wrangler deploy                       [deploys to Cloudflare]
```

### CI Flow (Weekly Update)

```
update-types.yml triggers
    |
    v
npm pack @cloudflare/workers-types    [fetch latest]
    |
    v
extract/extract.ts                    [re-extract IR]
    |
    v
data/workers-ir.json.new              [diff against committed]
    |
    v (if changed)
dune exec spiceflare-codegen --       [regenerate bindings]
    data/workers-ir.json
    packages/spiceflare/src/
    |
    v
dune build                            [type-check both packages]
    |
    v
Open PR with diffs                    [visible API surface changes]
```

## dune-project Configuration

**Confidence: HIGH** -- based on melange-json (multi-package, Melange + native, same pattern), melange-webapi (published Melange bindings), and cf_workers (Melange CF Workers bindings).

```dune
(lang dune 3.16)

(using melange 0.1)

(name spiceflare)

(version 4.20260317.1)

(generate_opam_files true)

(source (github paulbutcher/ocaml-spiceflare))

(license MIT)

(authors "Paul Butcher")

(maintainers "Paul Butcher")

;; ---- Package 1: The bindings (consumer-facing) ----

(package
 (name spiceflare)
 (synopsis "Melange bindings for the Cloudflare Workers API")
 (description
  "Type-safe OCaml external declarations for the full Cloudflare Workers
   runtime API surface, compiled via Melange to JavaScript. Covers KV, D1,
   R2, Durable Objects, Queues, AI, WebSocket, streams, and ~40 service
   modules. Auto-generated from @cloudflare/workers-types.")
 (depends
  (ocaml (>= 5.2))
  (melange (>= 4.0.0))))

;; ---- Package 2: The codegen tool ----

(package
 (name spiceflare-codegen)
 (synopsis "Code generator for spiceflare Cloudflare Workers bindings")
 (description
  "Reads a JSON intermediate representation extracted from
   @cloudflare/workers-types and emits Melange OCaml external binding
   declarations. Used to regenerate the spiceflare package when the
   Cloudflare API evolves.")
 (depends
  (ocaml (>= 5.2))
  (yojson (>= 2.0))
  (alcotest (and :with-test (>= 1.7)))))
```

### Key Design Points

1. **`(name spiceflare)`**: The project name matches the primary (consumer-facing) package. This is what `dune-release` uses as the primary package identity. Both `melange-json` and `melange-webapi` follow this pattern.

2. **`(using melange 0.1)`**: Required at the workspace level even though only one package uses Melange mode. Dune needs this to understand `(modes melange)` in any library stanza within the workspace.

3. **Single `(version)`**: Both packages share the same version, which tracks the `@cloudflare/workers-types` version. This is correct because both packages update together in the weekly CI flow.

4. **`(generate_opam_files true)`**: Dune generates `spiceflare.opam` and `spiceflare-codegen.opam` from the stanzas above. Never edit `.opam` files directly.

5. **Disjoint dependencies**: `spiceflare` depends on `melange`. `spiceflare-codegen` depends on `yojson` and `alcotest`. No overlap. This is intentional -- consumers of bindings should not be forced to install the codegen's dependencies.

## Package-Level Dune Stanzas

### spiceflare (Melange bindings library)

```dune
;; packages/spiceflare/src/dune
(library
 (name spiceflare)
 (public_name spiceflare)
 (modes melange))
```

**Why `(modes melange)` only:** The generated `.ml` files use `external` declarations with `[@@mel.send]`, `[@@mel.get]`, `[@@mel.new]`, etc. These are Melange-specific attributes. They cannot compile under native OCaml -- `melange` mode is the only valid compilation mode.

**Why no `(preprocess (pps melange.ppx))`:** The generated bindings use only `external` declarations and `[@@mel.obj]` attributes, which are handled by the Melange compiler directly, not by a PPX. No PPX preprocessing is needed.

**Type-checking happens automatically:** When `dune build` processes this library, Melange compiles all `.ml` files, verifying that types are consistent. This IS the compile-check. No separate test binary is needed for basic type-checking -- `dune build -p spiceflare` suffices.

### spiceflare bindings test (Melange compile test)

```dune
;; packages/spiceflare/test/dune
(melange.emit
 (target test_output)
 (libraries spiceflare))
```

```ocaml
(* packages/spiceflare/test/test_bindings.ml *)
(* Import all modules to verify they compile and link *)
let _ = Spiceflare.Kv.Kv_Namespace.t
let _ = Spiceflare.D1.D1_Database.t
let _ = Spiceflare.R2.R2_Bucket.t
(* ... one line per key module ... *)
```

**Why `melange.emit` and not just the library?** Building the library with `(modes melange)` type-checks the `.ml` files individually. But a `melange.emit` stanza also checks that modules can be resolved across the library boundary and that JS emission succeeds. This catches issues like unresolved cross-module references that a library build alone might miss.

**Confidence: MEDIUM** -- The library build alone might be sufficient. The `melange.emit` test is a belt-and-suspenders approach. If it proves to add too much CI time (unlikely for a bindings-only library), it can be removed.

### spiceflare-codegen (native OCaml library + executable)

```dune
;; packages/spiceflare-codegen/lib/dune
(library
 (name spiceflare_codegen)
 (public_name spiceflare-codegen.lib)
 (libraries yojson))
```

```dune
;; packages/spiceflare-codegen/bin/dune
(executable
 (name main)
 (public_name spiceflare-codegen)
 (package spiceflare-codegen)
 (libraries spiceflare_codegen))
```

```dune
;; packages/spiceflare-codegen/test/dune
(test
 (name test_all)
 (package spiceflare-codegen)
 (libraries spiceflare_codegen alcotest))
```

**Note on `public_name` and package inference:** The library `(public_name spiceflare-codegen.lib)` starts with `spiceflare-codegen`, so dune infers it belongs to the `spiceflare-codegen` package automatically. The executable needs an explicit `(package spiceflare-codegen)` because its `public_name` is exactly `spiceflare-codegen` (no dot separator). The test stanza also needs explicit `(package)` because it has no `public_name`.

### Demo Worker (not part of either package)

```dune
;; demo/src/dune
(melange.emit
 (target worker_output)
 (libraries spiceflare))
```

The demo is excluded from both opam packages. It depends on the `spiceflare` library at the workspace level (dune resolves it locally). It is NOT built by `dune build -p spiceflare` or `dune build -p spiceflare-codegen` -- it is only built by a bare `dune build` (which builds the whole workspace) or explicitly via `dune build @demo/src/all`.

## Build Order Implications

### What Can Be Parallelized

```
dune build
  |
  +-- spiceflare-codegen.lib    (native OCaml)    \
  +-- spiceflare-codegen.exe    (needs lib above)  |-- native compilation
  +-- spiceflare-codegen tests  (needs lib above)  /
  |
  +-- spiceflare library        (Melange mode)     \
  +-- spiceflare tests          (needs lib above)   |-- Melange compilation
  +-- demo worker               (needs lib above)  /
```

The native OCaml compilation (codegen) and the Melange compilation (bindings) are **fully independent** and can run in parallel. Dune handles this automatically.

### What Must Sequence

1. `spiceflare_codegen` lib must build before `spiceflare-codegen` exe and tests
2. `spiceflare` lib must build before `spiceflare` tests and demo
3. Within CI's weekly update: extract -> codegen -> copy to src -> build -> test

### Package-Scoped Builds

| Command | What It Builds | When Used |
|---------|----------------|-----------|
| `dune build -p spiceflare` | Bindings library only (Melange mode) | opam CI, release |
| `dune build -p spiceflare-codegen` | Codegen lib + exe + tests | opam CI, release |
| `dune build` | Everything: both packages + demo | Local dev, full CI |
| `dune runtest` | Both packages' tests | Full CI |

## CI Structure

### ci.yml (Every Push/PR)

```yaml
jobs:
  build-codegen:
    # Native OCaml only -- does NOT need melange
    steps:
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.2.x
      - run: opam install ./spiceflare-codegen.opam --deps-only --with-test
      - run: opam exec -- dune build -p spiceflare-codegen
      - run: opam exec -- dune runtest -p spiceflare-codegen

  build-bindings:
    # Needs melange
    steps:
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.2.x
      - run: opam install ./spiceflare.opam --deps-only
      - run: opam exec -- dune build -p spiceflare

  build-all:
    # Full workspace build including demo
    steps:
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.2.x
      - run: opam install . --deps-only --with-test
      - run: opam exec -- dune build
      - run: opam exec -- dune runtest
```

**Why separate jobs?** The `build-codegen` job runs without Melange installed, verifying that the codegen package has no accidental Melange dependency. The `build-bindings` job verifies the bindings compile under Melange. The `build-all` job is the integration check.

**Confidence: MEDIUM** -- Separating into three CI jobs is ideal but may be overkill initially. A single `build-all` job is simpler to start with. The separation becomes valuable when CI time exceeds a few minutes, or to verify dependency isolation.

### update-types.yml (Weekly)

The update workflow path changes from:
- `output/cf_workers_bindings/` to `packages/spiceflare/src/`

And the codegen executable name changes from:
- `dune exec spiceflare` to `dune exec spiceflare-codegen`

## Patterns to Follow

### Pattern 1: Public Name Prefix Convention

**What:** A library's `public_name` must start with its parent package's name, optionally followed by a dot and a suffix.

**When:** Always, in multi-package repos.

**Example:**
```dune
;; Library belongs to spiceflare-codegen package (inferred from public_name prefix)
(library
 (name spiceflare_codegen)
 (public_name spiceflare-codegen.lib)
 ...)

;; Library belongs to spiceflare package (exact match)
(library
 (name spiceflare)
 (public_name spiceflare)
 ...)
```

### Pattern 2: Generated Files as First-Class Source

**What:** The generated `.ml` files live in the published package's source directory and are committed to git. They are not treated as build artifacts.

**When:** The codegen is a development tool; the output is the consumer deliverable.

**Why:** Consumers should not need the codegen installed. The generated files must be `opam install`-able directly. Committing them also makes API surface changes visible in PR diffs.

**Example from ecosystem:** `melange-webapi` has hand-written `.ml` files committed directly. `ocaml-protoc` generates `.ml` files that are committed. This is standard practice for code generators in the OCaml ecosystem.

### Pattern 3: Package-Scoped Testing

**What:** Each package's test stanza explicitly declares `(package ...)` so that `dune runtest -p <pkg>` runs only that package's tests.

**When:** Always, in multi-package repos.

**Example:**
```dune
(test
 (name test_all)
 (package spiceflare-codegen)
 (libraries spiceflare_codegen alcotest))
```

### Pattern 4: Workspace-Only Components

**What:** Components that are not part of any published package (demo, extract/, data/) live at the workspace root and have no `(package)` field.

**When:** For development-only tooling and examples.

**Why:** `dune build -p <pkg>` ignores stanzas without a matching `(package)` field. This keeps the demo and extraction toolchain out of the published packages.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Cross-Package Build Dependencies

**What:** Making `spiceflare` depend on `spiceflare-codegen` at build time (e.g., having dune run the codegen as a build rule).

**Why bad:** Consumers installing the bindings would need the codegen and all its dependencies (yojson, etc.). It also makes the bindings package unbuildable in isolation.

**Instead:** Commit generated files. Run codegen manually or via CI. The two packages are buildable independently.

### Anti-Pattern 2: Shared Version with Different Semantics

**What:** Using the same version number but meaning different things for each package.

**Why bad:** Both packages track `@cloudflare/workers-types` version. If versions diverged, consumers couldn't tell which CF API version each package targets.

**Instead:** Single `(version)` in `dune-project`, shared by both packages. Both update together.

### Anti-Pattern 3: Melange PPX Where Not Needed

**What:** Adding `(preprocess (pps melange.ppx))` to a library that only uses `external` declarations.

**Why bad:** Adds an unnecessary build dependency and slows compilation. The Melange compiler handles `[@@mel.*]` attributes directly.

**Instead:** Only add `melange.ppx` if the library uses `%mel.raw`, `%mel.obj` expressions, or `[@@deriving]`-style PPX features.

### Anti-Pattern 4: Wrapper Module Over Generated Files

**What:** Creating a hand-written `spiceflare.ml` that re-exports all generated modules.

**Why bad:** Dune's library wrapping already creates a `Spiceflare` namespace module. Adding a manual wrapper creates conflicts or shadows the auto-generated wrapper.

**Instead:** Let dune's `(wrapped true)` (the default) handle namespacing. Consumers access `Spiceflare.Kv`, `Spiceflare.D1`, etc. automatically.

## Migration Path from Current Structure

The restructure requires moving files, not changing them:

| Current Location | New Location | Notes |
|------------------|-------------|-------|
| `lib/*.ml` | `packages/spiceflare-codegen/lib/*.ml` | Rename library: `spiceflare_lib` -> `spiceflare_codegen` |
| `bin/main.ml` | `packages/spiceflare-codegen/bin/main.ml` | Update library reference |
| `test/test_all.ml` | `packages/spiceflare-codegen/test/test_all.ml` | Update library reference |
| `output/cf_workers_bindings/*.ml` | `packages/spiceflare/src/*.ml` | The published library source |
| `output/cf_workers_bindings/dune` | `packages/spiceflare/src/dune` | Rewrite: uncomment + update |
| (new) | `packages/spiceflare/test/` | New compile-check test |
| (new) | `demo/` | New demo worker |
| `data/` | `data/` (unchanged) | Stays at workspace root |
| `extract/` | `extract/` (unchanged) | Stays at workspace root |

### Library Rename: `spiceflare_lib` -> `spiceflare_codegen`

The current library is named `spiceflare_lib` with no `public_name`. It must be renamed to `spiceflare_codegen` with `(public_name spiceflare-codegen.lib)` so that:
- It belongs to the `spiceflare-codegen` package
- It can be depended on by consumers who want to use the codegen as a library (edge case, but correct to support)
- The name `spiceflare` (without suffix) is reserved for the bindings library

### Internal Reference Updates

All references to `SpiceFlare_lib` in OCaml code become `Spiceflare_codegen`:
- `bin/main.ml`: `open Spiceflare_codegen` or qualified `Spiceflare_codegen.Ir_parse.parse_file`
- `test/test_all.ml`: same pattern

## Scalability Considerations

| Concern | At 1 CF API version | At 10 versions | At 100+ modules |
|---------|---------------------|----------------|-----------------|
| Build time | Negligible | N/A (only latest version) | Melange compiles ~43 files; fast |
| Package size | ~10K lines of .ml | N/A | May need `(include_subdirs unqualified)` if modules multiply |
| CI time | < 2 min | N/A | Split jobs if > 5 min |
| opam publish | One PR, two packages | Same | Same |

## dune-release Considerations

**Confidence: MEDIUM** -- based on dune-release docs and GitHub issue #442.

`dune-release` handles multi-package repos by default: it creates one tarball and one GitHub release, then submits opam files for ALL packages in the repo. Known issues:

1. **Synopsis selection bug:** dune-release may pick the synopsis from a random `.opam` file for the GitHub release description. The `(name spiceflare)` in `dune-project` should make it prefer the primary package, but this is the dune-release bug from issue #442. Workaround: verify the release description manually.

2. **Both packages released together:** This is the desired behavior -- both packages track the same CF API version and should always be released as a pair.

3. **Version tagging:** A single git tag (e.g., `4.20260317.1`) triggers the release of both packages. The `(version)` field in `dune-project` is shared.

## Sources

- [melange-json dune-project](https://github.com/melange-community/melange-json/blob/main/dune-project) -- real-world multi-package Melange + native OCaml repo (HIGH confidence)
- [melange-webapi dune-project](https://github.com/melange-community/melange-webapi) -- published Melange bindings library structure (HIGH confidence)
- [cf_workers dune-project](https://github.com/adrianparvino/cf_workers) -- prior art for Melange CF Workers bindings (HIGH confidence)
- [Melange build system docs](https://melange.re/unstable/build-system.html) -- `(modes melange)`, `melange.emit`, library setup (HIGH confidence)
- [Melange package management docs](https://melange.re/unstable/package-management.html) -- opam publishing for Melange (MEDIUM confidence, incomplete docs)
- [Dune opam file generation](https://dune.readthedocs.io/en/stable/howto/opam-file-generation.html) -- `(generate_opam_files true)`, multi-package stanzas (HIGH confidence)
- [dune-release multi-package issue #442](https://github.com/tarides/dune-release/issues/442) -- known synopsis bug with multiple packages (MEDIUM confidence, issue still open)
- [Dune package spec docs](https://dune.readthedocs.io/en/stable/concepts/package-spec.html) -- how `public_name` maps to packages (HIGH confidence)
- [Dune universal libraries preview](https://melange.re/blog/posts/dune-universal-libraries-preview) -- native + Melange in one project (MEDIUM confidence, feature incomplete)
