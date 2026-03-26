# Architecture

**Analysis Date:** 2026-03-26

## System Overview

spiceflare is a two-stage code generation pipeline that produces Melange OCaml `external` binding declarations for the Cloudflare Workers runtime API. It reads a JSON intermediate representation (IR) extracted from `@cloudflare/workers-types` (a TypeScript `.d.ts` file) and emits structured `.ml` files covering the full Workers API surface: KV, D1, R2, Durable Objects, Queues, AI, WebSocket, and ~40 other service modules.

The output `.ml` files can be consumed directly by any OCaml project targeting Cloudflare Workers via Melange.

## Architecture Pattern

**Two-stage offline code generator (compiler-style pipeline)**

- Stage 1 (TypeScript/Node.js): Extract a typed JSON IR from `@cloudflare/workers-types index.d.ts`
- Stage 2 (OCaml/dune): Read the JSON IR, resolve types, transform to a binding AST, emit `.ml` files

The OCaml stage is itself structured as a classic compiler pipeline: parse → resolve → transform → emit, with distinct typed ASTs at each boundary.

Key characteristics:
- No runtime component — the tool is run offline and its outputs are committed artifacts
- Strict separation between input IR types (`lib/ir.ml`) and output binding types (`lib/binding_ast.ml`)
- Pure functional transform: no side effects in `resolve.ml` or `transform.ml`; all I/O isolated to `ir_parse.ml` and `emit.ml`
- The committed `data/workers-ir.json` is the versioned diffable artifact — changes to the API surface are visible as JSON diffs

## Core Modules / Components

**Stage 1 — TypeScript extraction (`extract/`)**

- `extract/extract.ts`: Walks `index.d.ts` using `ts-morph`, emits `workers-ir.json`. Extracts classes, interfaces, type aliases, functions, and variables. Converts TypeScript AST nodes to a clean tagged-union JSON format.
- `extract/grouping.ts`: Assigns each TypeScript declaration to an output module file. Uses three strategies in priority order: (1) prefix-pattern regex rules (e.g. `^KV` → `kv`), (2) explicit name overrides, (3) auto-discovery — declarations sharing a PascalCase prefix are grouped together; singletons fall to `workers_types`.

**Stage 2 — OCaml codegen library (`lib/`, dune library `spiceflare_lib`)**

- `lib/ir.ml`: Input AST types mirroring `workers-ir.json`. Algebraic types for the TypeScript type system subset: `typ` (10 variants: `Ref`, `Array`, `Union`, `Function`, `Object`, etc.), `decl` (class/interface/type_alias/function/variable), and `module_group`. No logic — pure data definitions.
- `lib/ir_parse.ml`: Yojson deserialiser for `workers-ir.json` → `Ir.ir`. Dispatches on `"kind"` tags in the JSON. The only module that touches Yojson directly.
- `lib/resolve.ml`: Two-pass usage classifier. Pass 1 marks types appearing in parameter positions as `Input`; pass 2 marks return/property positions as `Output`. Builds a `Hashtbl`-backed `env` used by `transform.ml` to decide between `[@@mel.obj]` constructors (input interfaces) and plain OCaml records (output interfaces).
- `lib/naming.ml`: camelCase/PascalCase → snake_case conversion and OCaml keyword escaping. Uses structural acronym detection — uppercase runs (e.g. `KV`, `D1`, `URL`) are treated as atomic units without a hardcoded list.
- `lib/transform.ml`: The core mapping logic. Transforms `Ir.ir` → `Binding_ast.output_file list`. Applies all type mapping rules (primitives, `Promise`, generic containers, unions, intersections), class transform (abstract `t` + `make` constructor + method/property externals), interface transform (input → `[@@mel.obj]`, output → record), type alias transform, and global function/variable transform.
- `lib/binding_ast.ml`: Output AST for generated `.ml` files. Models OCaml type expressions (`ocaml_type`), Melange attributes (`mel_attr`: `Mel_new`, `Mel_send`, `Mel_get`, `Mel_set`, etc.), external declarations (`external_decl`), type declarations (`Abstract`, `Record`, `Warning_type`), and the full file structure (`output_file` → `ocaml_module list` + `item list`).
- `lib/emit.ml`: Pretty-printer using OCaml's `Format` module. Converts `Binding_ast.output_file list` to `.ml` source text and writes files to the output directory. Line width is fixed at 90 characters.

**CLI entry point (`bin/`)**

- `bin/main.ml`: Minimal CLI. Accepts `<workers-ir.json> <output-dir>` arguments, calls `Ir_parse.parse_file`, `Resolve.resolve`, `Transform.transform_ir`, `Emit.emit_all` in sequence with progress output.

## Data Flow

**Stage 1 — IR extraction:**

1. Developer runs `npm run extract -- package/index.d.ts ../data/workers-ir.json` in `extract/`
2. `extract.ts` loads `index.d.ts` via `ts-morph`, walks AST nodes
3. TypeScript declarations → `IRDeclaration[]` via `extractClassDecl`, `extractTypeAlias`, `extractFunction`, `extractVariable`
4. Each declaration is assigned to an output module name via `grouping.ts` (`assignModule` → prefix rules → auto-group)
5. Grouped `IRModuleGroup[]` serialised to `data/workers-ir.json` (committed to the repo)

**Stage 2 — Binding generation:**

1. `bin/main.ml` parses CLI args, calls `Ir_parse.parse_file "data/workers-ir.json"` → `Ir.ir`
2. `Resolve.resolve ir` → `env`: traverses all declarations, classifies every named type reference as `Input | Output | Both | Unknown` using a `Hashtbl`
3. `Transform.transform_ir env ir` → `Binding_ast.output_file list`: for each `module_group`, each `decl` is dispatched to `transform_class`, `transform_interface`, `transform_type_alias`, `transform_global_function`, or `transform_global_variable`
4. `Emit.emit_all ~dir files`: for each `output_file`, opens an `out_channel`, creates a `Format.formatter`, pretty-prints the binding AST, writes the `.ml` file to `output/cf_workers_bindings/`

**State management:**

- `Resolve.env` is the only mutable structure (a `Hashtbl` with mutable `usage` fields per declaration)
- All other transform functions are pure: they return new AST nodes without mutation
- `bin/main.ml` threads `env` through the pipeline explicitly

## Key Design Decisions

**Dual AST boundary (`ir.ml` / `binding_ast.ml`):**
The IR types exactly mirror the JSON schema with no interpretation. All semantic decisions (how to represent a TypeScript union, whether an interface is input or output) happen only in `transform.ml`. This makes the transform logic the single source of truth for all mapping rules and keeps parsing and emission trivially simple.

**Input/output usage classification drives interface representation:**
Interfaces used only as method arguments get `[@@mel.obj]` constructors (ergonomic construction from OCaml). Interfaces used only as return values get plain OCaml records (ergonomic pattern matching). This avoids a blanket choice and produces idiomatic bindings in both cases. The classification is computed in `resolve.ml` by scanning the entire IR before any transformation.

**Structural acronym detection in `naming.ml`:**
Rather than maintaining a hardcoded list of CF service acronyms (`KV`, `D1`, `R2`, etc.), the snake_case algorithm treats any run of uppercase letters optionally followed by digits as an atomic unit. New Cloudflare services work automatically.

**Module grouping is configurable without touching codegen:**
All module assignment logic lives in `extract/grouping.ts` (RULES array, OVERRIDES map, auto-group function), entirely separate from the OCaml generator. Updating rules for a new CF service requires only editing `grouping.ts`, not `lib/`.

**Committed IR as diffable artifact:**
`data/workers-ir.json` is committed to the repo. The automated `update-types.yml` CI workflow re-extracts the IR weekly and opens a PR if it changes. This makes API surface changes visible as structured diffs rather than opaque binary changes.

**No runtime — pure offline batch tool:**
`dune exec spiceflare` is run once to regenerate bindings. The generated `.ml` files are the deliverable. There is no server, daemon, or incremental rebuild involved.
