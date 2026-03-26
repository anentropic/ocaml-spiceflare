# Codebase Structure

**Analysis Date:** 2026-03-26

## Directory Layout

```
ocaml-spiceflare/
├── bin/                    # CLI executable (dune executable, public_name: spiceflare)
│   ├── main.ml             # Entry point: parse args, run pipeline
│   └── dune
├── lib/                    # Core codegen library (dune library: spiceflare_lib)
│   ├── ir.ml               # Input AST types (mirrors workers-ir.json schema)
│   ├── ir_parse.ml         # Yojson deserialiser: workers-ir.json → Ir.ir
│   ├── resolve.ml          # Type reference resolution + input/output classification
│   ├── naming.ml           # camelCase/PascalCase → snake_case, keyword escaping
│   ├── transform.ml        # IR → Binding_ast (all mapping rules)
│   ├── binding_ast.ml      # Output AST types (Melange binding structure)
│   ├── emit.ml             # Pretty-printer: Binding_ast → .ml source files
│   └── dune
├── extract/                # TypeScript extraction toolchain (Node.js / ts-morph)
│   ├── extract.ts          # Walks index.d.ts, emits workers-ir.json
│   ├── grouping.ts         # Module assignment rules (prefix patterns + auto-group)
│   ├── tsconfig.json
│   ├── package.json
│   ├── package-lock.json
│   └── node_modules/       # (gitignored) npm dependencies
├── test/                   # Alcotest suite
│   ├── test_all.ml         # All test cases (naming, ir_parse, emit)
│   ├── fixtures/           # (empty — inline test data used instead)
│   └── dune
├── data/
│   └── workers-ir.json     # Committed IR: versioned, diffable API surface snapshot
├── output/
│   └── cf_workers_bindings/  # Generated Melange .ml files (committed output)
│       ├── dune            # dune library wrapping generated files
│       ├── ai.ml
│       ├── d1.ml
│       ├── kv.ml
│       ├── r2.ml
│       ├── globals.ml
│       ├── workers_types.ml
│       └── ... (~40 .ml files total)
├── _notes/
│   └── cf-workers-melange-codegen.md  # Design doc / research notes
├── .github/
│   └── workflows/
│       ├── ci.yml              # Build + test + odoc on push/PR
│       └── update-types.yml    # Weekly: re-extract IR, regenerate, open PR if changed
├── _build/                 # (gitignored) dune build artifacts
├── _opam/                  # Local opam switch (OCaml 5.2 + yojson + alcotest)
├── dune-project            # Project name, version, package definition
├── spiceflare.opam         # Generated opam file (do not edit — edit dune-project)
├── .ocamlformat            # OCaml formatting config
├── DEVELOP.md              # Developer setup and pipeline documentation
└── cloudflare-workers-types-4.20260317.1.tgz  # Cached npm tarball
```

## Module Organization

**OCaml library (`lib/`, dune library name: `spiceflare_lib`)**

Modules follow a strict pipeline order with one-way dependencies:

```
ir_parse  ──► ir           (ir_parse opens Ir)
resolve   ──► ir           (resolve opens Ir)
transform ──► ir           (transform opens Ir)
transform ──► binding_ast  (transform opens Binding_ast)
transform ──► resolve      (transform calls Resolve.is_input_interface, Resolve.is_known_decl)
transform ──► naming       (transform calls Naming.module_name_of, Naming.ocaml_name_of_member)
emit      ──► binding_ast  (emit opens Binding_ast)
```

`ir.ml` and `binding_ast.ml` are pure data definition modules with no dependencies.
`naming.ml` has no dependencies on other lib modules.
No circular dependencies.

**TypeScript toolchain (`extract/`)**

- `extract.ts` imports `grouping.ts` for `assignModule`, `autoGroup`, and `SKIP`
- `grouping.ts` has no imports from `extract.ts`
- Both are compiled by `tsx` at runtime (no build step needed)

**CLI (`bin/`)**

`bin/main.ml` depends on `spiceflare_lib` only. It calls modules by their full qualified names: `SpiceFlare_lib.Ir_parse`, `SpiceFlare_lib.Resolve`, `SpiceFlare_lib.Transform`, `SpiceFlare_lib.Emit`.

## Entry Points

**OCaml CLI (`bin/main.ml`)**

- Built as dune executable, installed as `spiceflare`
- Invocation: `dune exec spiceflare -- data/workers-ir.json output/cf_workers_bindings/`
- Arguments: `<path-to-ir-json> <output-directory>`
- Pipeline: parse → resolve → transform → emit

**TypeScript extractor (`extract/extract.ts`)**

- Invocation: `cd extract && npm run extract -- package/index.d.ts ../data/workers-ir.json`
- Arguments: `<path-to-index.d.ts> <output-json-path>`
- Requires Node.js >= 18 and `npm install` in `extract/`

**Test runner**

- Invocation: `dune runtest` or `dune exec test/test_all.exe`
- Single test file: `test/test_all.ml` using Alcotest

## Configuration

| File | Purpose |
|------|---------|
| `dune-project` | Project name (`spiceflare`), version, OCaml/dune/yojson/alcotest dependencies |
| `spiceflare.opam` | Generated from `dune-project` — do not edit directly |
| `.ocamlformat` | OCaml formatting rules applied by `ocamlformat` |
| `extract/tsconfig.json` | TypeScript compiler options for `ts-morph` (ESNext, strict, noLib) |
| `extract/package.json` | npm dependencies: `ts-morph`, `tsx` |
| `.github/workflows/ci.yml` | CI: build + test + odoc on every push/PR |
| `.github/workflows/update-types.yml` | Scheduled weekly: re-extract IR, regenerate bindings, open PR |

**No runtime environment variables or `.env` files** — the tool is a pure offline batch process.

## Generated / Build Artifacts

**Committed generated artifacts (tracked in git):**

- `data/workers-ir.json`: JSON IR extracted from `@cloudflare/workers-types`. Updated by the weekly CI job. Treated as the versioned API surface snapshot.
- `output/cf_workers_bindings/*.ml` (~40 files): Melange OCaml bindings generated by Stage 2. All files are committed and regenerated as a unit.

**Not committed (gitignored):**

- `_build/`: dune build directory containing compiled OCaml objects, bytecode, and native executables
- `_opam/`: local opam switch with OCaml 5.2, yojson, alcotest, dune, odoc
- `extract/node_modules/`: npm packages for the extraction toolchain

## Where to Add New Code

**New type mapping rule** (e.g. a new TypeScript built-in):
- Add a case to `map_primitive_or_ref` or `map_type` in `lib/transform.ml`

**New Melange attribute** (e.g. `[@mel.scope]`):
- Add a variant to `mel_attr` in `lib/binding_ast.ml`
- Add a printer case in `emit.ml`'s `pp_mel_attr`

**New module assignment for a Cloudflare service**:
- Add a `GroupingRule` entry to the `RULES` array in `extract/grouping.ts`
- Or add an explicit entry to `OVERRIDES` if the name doesn't follow a prefix pattern

**New declaration kind transformation**:
- Add a case in `transform_decl` in `lib/transform.ml`
- Add the corresponding IR type variant in `lib/ir.ml` if needed

**New tests**:
- Add test cases to `test/test_all.ml` in the appropriate `Alcotest.run` suite block
- Inline JSON strings are used for IR parse tests; no fixture files are required

**New output module** (e.g. a new generated `.ml` file category):
- The module name comes from the grouping step in `extract/grouping.ts`
- No OCaml code changes needed — `transform_module_group` derives the filename from `mg_name`
