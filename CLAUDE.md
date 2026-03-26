<!-- GSD:project-start source:PROJECT.md -->
## Project

**spiceflare**

spiceflare is a two-stage code generator and its output: a complete set of Melange OCaml `external` bindings for the Cloudflare Workers runtime API. The generator (`spiceflare-codegen`) reads a JSON intermediate representation extracted from `@cloudflare/workers-types` and emits structured `.ml` files covering the full Workers API surface. The generated bindings (`spiceflare`) are the published deliverable — a first-class opam package that OCaml/Melange projects targeting Cloudflare Workers can depend on.

**Core Value:** Consumers get up-to-date, idiomatic Melange bindings for the entire CF Workers API without having to hand-author or maintain them — the codegen handles regeneration as the Cloudflare API evolves.

### Constraints

- **Tech stack**: OCaml >= 5.2, Node.js >= 18, dune >= 3.16, Melange (version TBD) for generated output
- **Naming**: `spiceflare` opam package = published bindings; `spiceflare-codegen` opam package = generator tool
- **Compatibility**: Generated bindings must work with whatever Melange version is current at publish time
- **No runtime**: Both packages are offline tools/artifacts — no server, daemon, or incremental build
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Primary Languages
- **OCaml** >= 5.2 — core codegen library and CLI executable
- **TypeScript** ~5.9 (via tsx runner) — extraction stage (`extract/extract.ts`, `extract/grouping.ts`)
## Frameworks & Libraries
- `yojson` 3.0.0 — JSON parsing and pretty-printing; deserialises `data/workers-ir.json` into the IR AST (`lib/ir_parse.ml`)
- `alcotest` 1.9.1 — unit test framework; used in `test/test_all.ml`
- `odoc` — documentation generation (with-doc dependency, triggered by `dune build @doc`)
- `ts-morph` 24.0.0 — TypeScript AST walking; drives extraction of `@cloudflare/workers-types` into JSON IR (`extract/extract.ts`)
- `typescript` 5.9.3 — TypeScript compiler (peer dependency of ts-morph)
- `tsx` 4.21.0 — zero-config TypeScript runner (executes `extract.ts` via `npm run extract`)
- `esbuild` 0.27.4 — bundler used internally by tsx
## Build System
- **Dune** 3.21.1 (installed), lang `3.16` declared in `dune-project`
- **npm** — manages the TypeScript extraction toolchain in `extract/`
## Package Management
- `opam` — package manager; `spiceflare.opam` is auto-generated from `dune-project`
- Local opam switch at `_opam/` (project-local, not committed)
- No separate lockfile; `spiceflare.opam` pins minimum version constraints
- `npm` with `extract/package-lock.json` (lockfileVersion 2, committed)
- Dependencies declared in `extract/package.json`
## Runtime Requirements
- **OCaml** >= 5.2 (strict — opam constraint)
- **Node.js** >= 18 (extraction stage only; CI pins Node 22 via `actions/setup-node@v4`)
- **opam** — required to install OCaml dependencies and run dune in CI
- **npm** — required to install extraction toolchain
## Development Tools
- `ocamlformat` 0.27.0 — configured via `.ocamlformat` (`profile = default`, `version = 0.27.0`)
- `merlin` — present in `_opam/bin/`, provides type-aware completion (Dune generates `.merlin-conf` files in `_build/`)
- TypeScript strict mode enforced via `extract/tsconfig.json` (`"strict": true`)
- TypeScript target: ES2022, module system: Node16
- GitHub Actions (`.github/workflows/`) — see INTEGRATIONS.md for details
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Conventions
- Snake_case module stems: `binding_ast.ml`, `ir_parse.ml`, `transform.ml`
- File names match module names exactly (dune default)
- No `.mli` interface files — all modules expose their full signature
- Public functions: `snake_case` — `to_snake_case`, `escape_keyword`, `parse_file`, `emit_all`
- Private helpers: `snake_case` with contextual prefix — `str_field`, `bool_field`, `list_field`
- Predicate helpers use `is_` prefix — `is_upper`, `is_lower`, `is_known_decl`, `is_input_interface`
- Constructor helpers use descriptive names — `labelled_param`, `optional_param`, `positional_param`
- Setter bindings use `set_` prefix — `set_<property_name>` (generated output convention)
- Variant constructors: `PascalCase` — `Ref`, `Array`, `Union`, `Tname`, `Tapply`, `Mel_new`, `Mel_send`
- Record field names use module-specific short prefixes:
- Type aliases lowercase: `usage`, `env`, `label`
- Variant constructors for classifications use backtick polymorphic variants: `` `Nullable ``, `` `Fallback ``
- Let bindings: `snake_case` — `ir_path`, `output_dir`, `kv_ns`
- Loop/iteration variables: short names — `i`, `c`, `m`, `d`, `p`, `ov`
- Accumulator variables: `acc`, `buf`
- Mutable refs: descriptive noun — `modules`, `toplevel`, `found`
- Library is `spiceflare_lib` (dune library name)
- Called as `SpiceFlare_lib.Module_name.function` from the executable
- `module J = Yojson.Safe.Util` — short alias for heavily-used modules
## Code Style
- `ocamlformat` version `0.27.0`, profile `default`
- Config at `.ocamlformat`
- 2 spaces (ocamlformat default profile)
- Dune files use 1-space indentation
- `Format.pp_set_margin fmt 90` used in both `emit.ml` and `test_all.ml`, establishing 90 as the project line width
- Horizontal rule comments divide logical sections within a file:
- Used consistently in `transform.ml`, `emit.ml`, `resolve.ml`
- `open Ir` and `open Binding_ast` used at top of files that operate extensively on those types
- Avoids qualifying every variant/record constructor
- Short local alias `module J = Yojson.Safe.Util` used in `ir_parse.ml`
## Common Patterns
- `let ( let* ) = Result.bind` defined locally in `ir_parse.ml` for monadic error threading (though currently used sparingly — JSON defaults to empty on missing fields rather than propagating errors)
| other ->
## Error Handling
| other ->
## Documentation Style
- `ir.ml`: `(** Input AST types mirroring our custom workers-ir.json schema. ... *)`
- `naming.ml`: `(** Name conversion: camelCase/PascalCase to snake_case, keyword escaping. ... *)`
- `emit.ml`: `(** Pretty-print Binding AST as .ml source files. Uses the Format module for readable output with proper line breaking. *)`
| Tname of string  (** e.g., "string", "float", "t", "Kv.t" *)
| Tapply of ocaml_type * ocaml_type list  (** e.g., string Js.Promise.t *)
| Tvar of string  (** 'a, 'b *)
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
## Architecture Pattern
- Stage 1 (TypeScript/Node.js): Extract a typed JSON IR from `@cloudflare/workers-types index.d.ts`
- Stage 2 (OCaml/dune): Read the JSON IR, resolve types, transform to a binding AST, emit `.ml` files
- No runtime component — the tool is run offline and its outputs are committed artifacts
- Strict separation between input IR types (`lib/ir.ml`) and output binding types (`lib/binding_ast.ml`)
- Pure functional transform: no side effects in `resolve.ml` or `transform.ml`; all I/O isolated to `ir_parse.ml` and `emit.ml`
- The committed `data/workers-ir.json` is the versioned diffable artifact — changes to the API surface are visible as JSON diffs
## Core Modules / Components
- `extract/extract.ts`: Walks `index.d.ts` using `ts-morph`, emits `workers-ir.json`. Extracts classes, interfaces, type aliases, functions, and variables. Converts TypeScript AST nodes to a clean tagged-union JSON format.
- `extract/grouping.ts`: Assigns each TypeScript declaration to an output module file. Uses three strategies in priority order: (1) prefix-pattern regex rules (e.g. `^KV` → `kv`), (2) explicit name overrides, (3) auto-discovery — declarations sharing a PascalCase prefix are grouped together; singletons fall to `workers_types`.
- `lib/ir.ml`: Input AST types mirroring `workers-ir.json`. Algebraic types for the TypeScript type system subset: `typ` (10 variants: `Ref`, `Array`, `Union`, `Function`, `Object`, etc.), `decl` (class/interface/type_alias/function/variable), and `module_group`. No logic — pure data definitions.
- `lib/ir_parse.ml`: Yojson deserialiser for `workers-ir.json` → `Ir.ir`. Dispatches on `"kind"` tags in the JSON. The only module that touches Yojson directly.
- `lib/resolve.ml`: Two-pass usage classifier. Pass 1 marks types appearing in parameter positions as `Input`; pass 2 marks return/property positions as `Output`. Builds a `Hashtbl`-backed `env` used by `transform.ml` to decide between `[@@mel.obj]` constructors (input interfaces) and plain OCaml records (output interfaces).
- `lib/naming.ml`: camelCase/PascalCase → snake_case conversion and OCaml keyword escaping. Uses structural acronym detection — uppercase runs (e.g. `KV`, `D1`, `URL`) are treated as atomic units without a hardcoded list.
- `lib/transform.ml`: The core mapping logic. Transforms `Ir.ir` → `Binding_ast.output_file list`. Applies all type mapping rules (primitives, `Promise`, generic containers, unions, intersections), class transform (abstract `t` + `make` constructor + method/property externals), interface transform (input → `[@@mel.obj]`, output → record), type alias transform, and global function/variable transform.
- `lib/binding_ast.ml`: Output AST for generated `.ml` files. Models OCaml type expressions (`ocaml_type`), Melange attributes (`mel_attr`: `Mel_new`, `Mel_send`, `Mel_get`, `Mel_set`, etc.), external declarations (`external_decl`), type declarations (`Abstract`, `Record`, `Warning_type`), and the full file structure (`output_file` → `ocaml_module list` + `item list`).
- `lib/emit.ml`: Pretty-printer using OCaml's `Format` module. Converts `Binding_ast.output_file list` to `.ml` source text and writes files to the output directory. Line width is fixed at 90 characters.
- `bin/main.ml`: Minimal CLI. Accepts `<workers-ir.json> <output-dir>` arguments, calls `Ir_parse.parse_file`, `Resolve.resolve`, `Transform.transform_ir`, `Emit.emit_all` in sequence with progress output.
## Data Flow
- `Resolve.env` is the only mutable structure (a `Hashtbl` with mutable `usage` fields per declaration)
- All other transform functions are pure: they return new AST nodes without mutation
- `bin/main.ml` threads `env` through the pipeline explicitly
## Key Design Decisions
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
