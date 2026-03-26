# Technology Stack

**Analysis Date:** 2026-03-26

## Primary Languages

- **OCaml** >= 5.2 — core codegen library and CLI executable
- **TypeScript** ~5.9 (via tsx runner) — extraction stage (`extract/extract.ts`, `extract/grouping.ts`)

## Frameworks & Libraries

**OCaml (opam):**
- `yojson` 3.0.0 — JSON parsing and pretty-printing; deserialises `data/workers-ir.json` into the IR AST (`lib/ir_parse.ml`)
- `alcotest` 1.9.1 — unit test framework; used in `test/test_all.ml`
- `odoc` — documentation generation (with-doc dependency, triggered by `dune build @doc`)

**TypeScript (npm, `extract/` only):**
- `ts-morph` 24.0.0 — TypeScript AST walking; drives extraction of `@cloudflare/workers-types` into JSON IR (`extract/extract.ts`)
- `typescript` 5.9.3 — TypeScript compiler (peer dependency of ts-morph)
- `tsx` 4.21.0 — zero-config TypeScript runner (executes `extract.ts` via `npm run extract`)
- `esbuild` 0.27.4 — bundler used internally by tsx

## Build System

- **Dune** 3.21.1 (installed), lang `3.16` declared in `dune-project`
  - `dune build` — compiles OCaml library and CLI executable
  - `dune runtest` — runs alcotest suite
  - `dune build @doc` — builds odoc documentation
  - `dune exec spiceflare` — runs the CLI to generate bindings
- **npm** — manages the TypeScript extraction toolchain in `extract/`
  - `npm run extract` — invokes `tsx extract.ts <input> <output>`

## Package Management

**OCaml:**
- `opam` — package manager; `spiceflare.opam` is auto-generated from `dune-project`
- Local opam switch at `_opam/` (project-local, not committed)
- No separate lockfile; `spiceflare.opam` pins minimum version constraints

**TypeScript/Node:**
- `npm` with `extract/package-lock.json` (lockfileVersion 2, committed)
- Dependencies declared in `extract/package.json`

## Runtime Requirements

- **OCaml** >= 5.2 (strict — opam constraint)
- **Node.js** >= 18 (extraction stage only; CI pins Node 22 via `actions/setup-node@v4`)
- **opam** — required to install OCaml dependencies and run dune in CI
- **npm** — required to install extraction toolchain

## Development Tools

**Formatting:**
- `ocamlformat` 0.27.0 — configured via `.ocamlformat` (`profile = default`, `version = 0.27.0`)

**Editor/IDE support:**
- `merlin` — present in `_opam/bin/`, provides type-aware completion (Dune generates `.merlin-conf` files in `_build/`)

**Linting/Type checking:**
- TypeScript strict mode enforced via `extract/tsconfig.json` (`"strict": true`)
- TypeScript target: ES2022, module system: Node16

**CI:**
- GitHub Actions (`.github/workflows/`) — see INTEGRATIONS.md for details

---

*Stack analysis: 2026-03-26*
