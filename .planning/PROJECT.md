# spiceflare

## What This Is

spiceflare is a two-stage code generator and its output: a complete set of Melange OCaml `external` bindings for the Cloudflare Workers runtime API. The generator (`spiceflare-codegen`) reads a JSON intermediate representation extracted from `@cloudflare/workers-types` and emits structured `.ml` files covering the full Workers API surface. The generated bindings (`spiceflare`) are the published deliverable — a first-class opam package that OCaml/Melange projects targeting Cloudflare Workers can depend on.

## Core Value

Consumers get up-to-date, idiomatic Melange bindings for the entire CF Workers API without having to hand-author or maintain them — the codegen handles regeneration as the Cloudflare API evolves.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ TypeScript IR extraction from `@cloudflare/workers-types` via ts-morph — existing
- ✓ OCaml Melange binding generation from JSON IR (parse → resolve → transform → emit) — existing
- ✓ Full Workers API surface coverage: KV, D1, R2, Durable Objects, Queues, AI, WebSocket, streams, globals (~40 modules) — existing
- ✓ Prefix-based + auto-discovery module grouping (zero config for new CF services) — existing
- ✓ Input/output usage classification: `[@@mel.obj]` for input interfaces, plain records for output — existing
- ✓ Structural acronym detection in naming (`KV`, `D1`, `R2` handled without hardcoded list) — existing
- ✓ Committed `data/workers-ir.json` as diffable versioned artifact — existing
- ✓ CI: build/test on every push, weekly automated IR update PR — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] Restructure into two opam packages in one repo: `spiceflare` (bindings) + `spiceflare-codegen` (generator tool)
- [ ] Fix compile blockers in generated bindings (`ReadableStream`/`WritableStream` unresolved, `dune` stanza inactive)
- [ ] Codegen-emitted compile-checking test suite that verifies every binding type-checks under Melange
- [ ] Deployable demo CF Worker in-repo (exercises key bindings: KV, D1, R2, fetch, env) with wrangler config
- [ ] Documentation for the bindings package: usage guide, per-module reference (odoc), JS shim snippet
- [ ] Documentation for the codegen tool: expand DEVELOP.md, design rationale, how to extend
- [ ] opam publish setup for both `spiceflare` and `spiceflare-codegen`
- [ ] GitHub Releases CI automation (tag → generate → publish opam PR)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- OCaml wrapper layer (typed routing, Request variants, Ctx helpers) — consumers build this per project; raw bindings are the right boundary
- npm publishing of the JS entry-point shim — the import path (`./_build/default/...`) is project-specific; document as a copy-paste snippet instead
- Separate demo repo — in-repo demo is sufficient and easier to keep in sync with bindings
- Cloudflare REST API bindings — separate package, different domain
- ReasonML syntax output — OCaml syntax is the default; ReasonML is a distinct ecosystem
- Wasm bindings — separate runtime path, out of scope for v1

## Context

The codegen pipeline is complete and working. The two-stage design (TS extraction → OCaml codegen) is sound and matches the architecture described in `_notes/cf-workers-melange-codegen.md`. Key known issues in the current generated output (from `.planning/codebase/CONCERNS.md`):

- `ReadableStream` / `WritableStream` references are unqualified bare type names — will fail to compile in any Melange project; fix is to qualify them as `Streams.Readable_Stream.t`
- The `output/cf_workers_bindings/dune` library stanza is entirely commented out — generated bindings are not currently buildable from this repo
- Class inheritance (`extends`/`implements`) is parsed but not used — subclass types are independent, not related in OCaml
- `Bind` module for heterogeneous input unions is partially implemented (AST + emitter exist, transform stage doesn't emit it yet)
- Numeric overload suffixes (`get_2`, `put_2`) exist where purpose-based names should be used

The JS entry-point shim is ~3 lines, permanent per project, and explicitly out of scope for the generator per design intent:
```js
// worker.js — hand-authored, checked in per project
import { fetch } from './_build/default/output/Worker.js';
export default { fetch };
```

Prior art: `adrianparvino/cf_workers` (hand-authored Melange/Workers bindings, informed the binding conventions).

## Constraints

- **Tech stack**: OCaml >= 5.2, Node.js >= 18, dune >= 3.16, Melange (version TBD) for generated output
- **Naming**: `spiceflare` opam package = published bindings; `spiceflare-codegen` opam package = generator tool
- **Compatibility**: Generated bindings must work with whatever Melange version is current at publish time
- **No runtime**: Both packages are offline tools/artifacts — no server, daemon, or incremental build

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| `spiceflare` package name = generated bindings (not codegen) | Consumers install bindings, not the generator; the deliverable deserves the primary name | — Pending |
| JS shim documented, not npm-published | Import path is project-specific (`_build/default/...`); 3-line snippet doesn't justify npm maintenance overhead | — Pending |
| Codegen'd compile-checking test suite | The generator has all type information needed to emit type-checking tests; this is more complete than hand-authored tests | — Pending |
| Demo Worker in-repo (not separate repo) | Easier to keep in sync; serves as live integration test for the bindings | — Pending |
| Two opam packages in one repo | Codegen and bindings have the same release cadence (tied to CF API versions); monorepo simplifies CI | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-03-26 after initialization*
