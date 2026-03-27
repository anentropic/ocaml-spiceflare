# Phase 1: Compilable Bindings - Research

**Researched:** 2026-03-27
**Domain:** OCaml/Melange code generation, dune build system, Cloudflare Workers API bindings
**Confidence:** HIGH

## Summary

Phase 1 requires fixing the codegen output so that generated `.ml` files compile under Melange, then emitting a test suite that verifies compilation. The investigation uncovered **five categories of compile-blocking issues**, not just the two (ReadableStream/WritableStream) previously known:

1. **Cross-module type references** (257 unique triples, ~445 occurrences) -- declarations referencing types from other files emit `Module.t` without the file-level qualifier (e.g., `Body.t` instead of `Request.Body.t`)
2. **Unqualified stream types** (the known BIND-01 issue) -- `readable_stream`/`writable_stream` bare names emitted by hardcoded cases in `transform.ml` lines 51-54
3. **Leaking type parameters** (~20 occurrences) -- TypeScript generics like `T`, `R`, `W`, `I`, `O` appear as bare capitalized names instead of OCaml type variables
4. **Forward reference ordering** (100+ within-file cases across 30+ files) -- modules within a file reference modules defined later, which OCaml's sequential module system rejects
5. **dune/Melange infrastructure** -- library stanza is commented out, `(using melange 0.1)` missing, Melange not installed, dune lang version needs bump from 3.16 to 3.18

The BIND-02 (Bind modules) and BIND-03 (inheritance aliases) requirements are additional codegen enhancements on top of these compile fixes.

**Primary recommendation:** Fix cross-module qualification and forward-reference ordering FIRST (they are the highest-volume blockers), then address stream types, type params, Bind modules, and inheritance -- in that order. Install Melange 6.0.1-54 on a new OCaml 5.4 switch. Use a `melange.emit` stanza (not just `(library (modes melange))`) to trigger actual compilation.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BIND-01 | Generated bindings compile -- ReadableStream/WritableStream qualified to correct module paths | Cross-module qualification system (fixes streams AND all 257 other cross-module ref triples). Forward-reference ordering fix. Type param leak fix. See Architecture Patterns section for implementation approach. |
| BIND-02 | Heterogeneous input unions emit Bind modules with typed smart constructors | 68 Bind candidates identified in the IR. `classify_union` needs a third case. Must detect input position at `transform_param` level. See Code Examples section. |
| BIND-03 | Single-inheritance class chains emit `type t = SuperModule.t` | 60 extends chains found (21 same-module, 39 cross-module). Need new `Alias` type_decl variant in binding_ast.ml or emit type alias in existing Abstract variant. Extends-Error chains should NOT alias (Error maps to Js.Exn.t). |
| PKG-01 | Bindings dune stanza activated, `(using melange 0.1)` in dune-project | Requires OCaml 5.4 switch + melange 6.0.1-54 install. dune lang must be bumped to 3.18. melange.emit stanza needed to trigger compilation. |
| TEST-01 | Codegen emits compile-checking test suite alongside bindings | Parallel directory `output/cf_workers_bindings_test/` with one `_test.ml` per module. Each test file opens the bindings module and references key types/externals. Own dune stanza with `melange.emit` to trigger compilation. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| melange | 6.0.1-54 | OCaml-to-JS compiler for generated bindings | Only version supporting OCaml 5.4; PKG-05 requires `melange >= 6.0.1` |
| ocaml | 5.4.0 | Compiler for both codegen tool and generated output | PKG-05 specifies `ocaml >= 5.4 & < 5.5`; melange 6.0.1-54 requires this range |
| dune | >= 3.18 | Build system | melange 6.0.1-54 depends on `dune >= 3.18`; installed version is 3.21.1 (sufficient) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| yojson | >= 2.0 | JSON parsing for IR | Already installed, unchanged |
| alcotest | >= 1.7 | Unit tests for codegen | Already installed, unchanged |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| OCaml 5.4 switch | OCaml 5.2 + melange 6.0.1-52 | Would work but contradicts PKG-05 requirement for `>= 5.4`. Better to switch now. |
| melange.emit for tests | Plain `(library (modes melange))` | Library stanza alone does NOT trigger compilation -- dune only type-checks melange libraries when something depends on them. melange.emit is required. |

**Installation:**
```bash
# Create new opam switch (current is OCaml 5.2, melange not installed)
opam switch create . 5.4.0 --deps-only
opam install melange.6.0.1-54
```

**Version verification:**
- melange 6.0.1-54: verified available via `opam info melange.6.0.1-54` -- depends on ocaml >= 5.4 & < 5.5, dune >= 3.18
- ocaml 5.4.0: verified available via `opam switch list-available`
- dune 3.21.1: installed, exceeds 3.18 requirement

## Architecture Patterns

### Fix 1: Cross-Module Type Qualification (BIND-01, highest priority)

**What:** When `map_type` or `map_primitive_or_ref` resolves a known declaration, it currently emits `Tname (Naming.module_name_of name ^ ".t")` which produces e.g. `Body.t`. When the declaration lives in a DIFFERENT file, this fails because `Body` is a submodule of `Request` (from `request.ml`).

**Current code (transform.ml:67-70):**
```ocaml
| Ref { name; args } when Resolve.is_known_decl env name ->
    let base = Tname (Naming.module_name_of name ^ ".t") in
    ...
```

**Required change:** Thread `current_module_name` (the `mg_name` of the module group being transformed) through `map_type`. When the resolved declaration's `module_name` (from `Resolve.find_decl`) differs from `current_module_name`, prepend the file-level module name.

**CRITICAL naming subtlety:** dune's file-level module name is `String.capitalize_ascii` of the filename stem (first letter only). This differs from `Naming.module_name_of`:
- `workers_types.ml` -> dune module `Workers_types` (NOT `Workers_Types`)
- `form_data.ml` -> dune module `Form_data` (NOT `Form_Data`)
- `durable_object.ml` -> dune module `Durable_object` (NOT `Durable_Object`)

There are **7 module groups** with underscores where this distinction matters: `durable_object`, `form_data`, `html_rewriter`, `rate_limit`, `sync_kv`, `tail_events`, `workers_types`.

**Implementation pattern:**
```ocaml
(* In resolve.ml -- add a helper *)
let file_module_of env name =
  match Hashtbl.find_opt env.decls name with
  | Some info -> Some (String.capitalize_ascii info.module_name)
  | None -> None

(* In transform.ml -- thread current module through map_type *)
let rec map_type env ~current_module (t : Ir.typ) : ocaml_type =
  ...
  | Ref { name; args } when Resolve.is_known_decl env name ->
    let decl_file_module = Resolve.file_module_of env name in
    let current_file_module = String.capitalize_ascii current_module in
    let prefix =
      match decl_file_module with
      | Some m when m <> current_file_module -> m ^ "."
      | _ -> ""
    in
    let base = Tname (prefix ^ Naming.module_name_of name ^ ".t") in
    ...
```

**Scope:** Affects `map_type`, `map_primitive_or_ref`, `classify_union`, `transform_param`, and all callers that currently pass `env` -- they must now also pass `~current_module`.

### Fix 2: Forward Reference Ordering

**What:** Generated modules within each `.ml` file are emitted in the order declarations appear in the IR. OCaml requires that module definitions appear before their references (no mutual recursion between `module X = struct ... end` blocks without `module rec`).

**Scale:** 100+ forward-reference pairs across 30+ files. Every major file has this issue.

**Recommended approach:** Topological sort of declarations within each module group before emitting. Build a dependency graph from each declaration's type references to other declarations in the same module group, then emit in dependency order. Cycles (mutual recursion) can be broken by emitting abstract type aliases.

**Implementation location:** `transform_module_group` in `transform.ml` currently emits declarations in `mg.mg_declarations` order. Add a sorting pass here or in a new `sort.ml` module.

**Cycle handling:** If two declarations mutually reference each other (e.g., A.t uses B.t and B.t uses A.t), emit forward type declarations:
```ocaml
(* Forward declaration *)
module B_forward = struct type t end

module A = struct
  type t = { b : B_forward.t }
end

module B = struct
  type t = { a : A.t }
end
```

Alternatively, use `module rec` but this is more complex and may not work for all cases under Melange.

### Fix 3: Type Parameter Leaking

**What:** TypeScript generic type parameters (T, R, W, I, O, etc.) appear as `Ref {name="T"; args=[]}` in the IR when used inside member type expressions. The extraction script correctly marks them as `type_param` at the declaration level but uses `ref` inside member bodies. `map_type` sees them as unknown refs and emits the bare name `T` instead of `'t` (a valid OCaml type variable).

**Scope:** 10 unique type parameter names used across the IR: `Args`, `ExpectedValue`, `InputOptions`, `Metadata`, `Name`, `Options`, `T`, `This`, `Type`, `U`. None collide with actual declaration names (verified). ~20 occurrences in generated output.

**Fix approach (in transform.ml):** Thread the current declaration's `d_type_params` and method's `mo_type_params` through `map_type`. When a `Ref` name matches a type parameter name, treat it as `Tvar ("'" ^ String.lowercase_ascii name)` instead of looking it up as a declaration.

```ocaml
(* Add type_params parameter to map_type *)
let rec map_type env ~current_module ~type_params (t : Ir.typ) : ocaml_type =
  match t with
  | Ref { name; args = [] } when List.exists (fun tp -> tp.tp_name = name) type_params ->
    Tvar ("'" ^ String.lowercase_ascii name)
  | ...
```

### Fix 4: ReadableStream/WritableStream Hardcoded Cases

**What:** `transform.ml` lines 51-54 hardcode `Tname "readable_stream"` and `Tname "writable_stream"`. These are bare, unqualified names. The actual types are `Streams.Readable_Stream.t` and `Streams.Writable_Stream.t`.

**Fix:** Remove the hardcoded cases entirely. With cross-module qualification (Fix 1), `ReadableStream` and `WritableStream` will be resolved normally through `is_known_decl` and qualified as `Streams.Readable_Stream.t` and `Streams.Writable_Stream.t` automatically.

The `ReadableStream` variable declaration in `globals` module should be handled separately (it's already a `Variable` kind, not a type reference).

### Fix 5: BIND-02 -- Bind Module Generation

**What:** `classify_union` currently only produces `` `Nullable `` or `` `Fallback ``. The `Bind` module infrastructure exists in `binding_ast.ml` and `emit.ml` but is never constructed by `transform.ml`.

**68 Bind candidates** identified in input position. Common patterns:
- `string | SomeOptions` (crypto algorithms)
- `ArrayBuffer | ArrayBufferView` (crypto data)
- `string | URL` (fetch/cache)
- `ReadableStream | ArrayBuffer | ArrayBufferView | string | Blob | null` (R2 put)
- `string:"gzip" | string:"deflate" | string:"deflate-raw"` (compression format)

**Architecture challenge:** `classify_union` in `map_union` doesn't know if the union appears in input position. The fix must detect input position at the call site (`transform_param` or when processing method parameters).

**Recommended approach:**
1. Add a `~position:[ `Input | `Output | `Unknown ]` parameter to `map_type` (or handle at `transform_param` level)
2. In `classify_union`, add a third case for finite non-nullable unions with 2-5 concrete members
3. When in input position and the union is finite, emit a `Bind` item instead of `'a Js.t`
4. Name the Bind constructors after the member types (e.g., `string` -> `of_string`, `URL.t` -> `of_url`)

### Fix 6: BIND-03 -- Inheritance Aliases

**What:** 60 extends chains found. Currently all ignored. Need to emit `type t = SuperModule.t` for single-inheritance cases.

**Categories of extends chains:**
- **Extends Error (17 cases):** `XxxError extends Error` -- should NOT alias since Error maps to `Js.Exn.t` (a Melange built-in). Keep abstract `type t`.
- **Same-module single inheritance (9 cases):** e.g., `File extends Blob`, `FixedLengthStream extends IdentityTransformStream`. Emit `type t = Parent_Module.t`.
- **Cross-module single inheritance (15 cases):** e.g., `DigestStream extends WritableStream`, `WebSocket extends EventTarget`. Emit `type t = File_Module.Parent_Module.t`.
- **Extends Record (2 cases):** `RequestInitCfProperties extends Record` -- skip (Record is a TS utility type).
- **Interface extends (multiple):** e.g., `R2ObjectBody extends R2Object`, `Response extends Body`. These need the same alias treatment.

**Implementation:** Add an `Alias` variant to `type_decl` in `binding_ast.ml`:
```ocaml
type type_decl =
  | Abstract of { name : string; doc : string option }
  | Alias of { name : string; target : ocaml_type; doc : string option }
  | Record of { ... }
  | Warning_type of { ... }
```

In `transform_class`/`transform_interface`, check `d.d_extends`:
- If exactly one extends clause, and parent is a known declaration (not Error/Record), emit `Alias` instead of `Abstract`
- Qualify the parent path using the same cross-module logic from Fix 1

### Recommended Project Structure
```
output/
  cf_workers_bindings/
    dune              # (library (name cf_workers_bindings) (modes melange))
    *.ml              # Generated binding files (43 files)
  cf_workers_bindings_test/
    dune              # (melange.emit (target test_output) (libraries cf_workers_bindings))
    *_test.ml         # Generated test files (43 files)
```

### Anti-Patterns to Avoid
- **Using `Naming.module_name_of` for file-level module names:** This produces `Workers_Types` when dune expects `Workers_types`. Use `String.capitalize_ascii` for file-level modules.
- **Using `(library (modes melange))` without `melange.emit`:** Melange libraries are not compiled by `dune build` alone. A `melange.emit` stanza (or another library/emit depending on it) is required to trigger type-checking.
- **Modifying the OCaml 5.2 switch in place:** melange 6.0.1-54 requires OCaml 5.4. Create a new project-local switch rather than trying to upgrade the existing one.
- **Emitting `module rec` for forward references:** Prefer topological sort. `module rec` has restrictions under Melange and adds syntactic complexity.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Topological sort | Custom DFS sort | `Stdlib` + simple DFS on adjacency list | Well-understood algorithm; only ~30 lines of OCaml needed. Don't import a graph library for this. |
| Module ordering | Alphabetical sort hack | Proper dependency-aware topological sort | Alphabetical would randomly fix some cases but break others |
| Cross-module name resolution | String concatenation heuristics | Use `Resolve.env` which already maps decl -> module_name | The data is already there; just needs to be consulted |

## Common Pitfalls

### Pitfall 1: File-Level vs Declaration-Level Module Names
**What goes wrong:** Using `Naming.module_name_of` (which capitalizes each underscore-separated word) for file-level modules produces names like `Workers_Types` when dune creates `Workers_types`.
**Why it happens:** dune's module name derivation only capitalizes the first character of the filename stem.
**How to avoid:** Use `String.capitalize_ascii mg_name` for file-level modules; use `Naming.module_name_of d.d_name` only for declaration-level submodules.
**Warning signs:** `Unbound module Workers_Types` compile error.

### Pitfall 2: Melange Libraries Don't Auto-Compile
**What goes wrong:** Uncommenting the library stanza and running `dune build` succeeds -- but nothing was actually checked because Melange libraries with `(modes melange)` are only compiled when something depends on them.
**Why it happens:** dune treats melange-mode libraries as lazy; they produce no artifacts on their own.
**How to avoid:** Add a `melange.emit` stanza that depends on the library. Use `dune build @melange` to trigger it.
**Warning signs:** `dune build` succeeds on obviously broken code.

### Pitfall 3: opam Switch Incompatibility
**What goes wrong:** Attempting to install melange 6.0.1-54 into the existing OCaml 5.2 switch fails with dependency conflicts.
**Why it happens:** melange 6.0.1-54 requires `ocaml >= 5.4 & < 5.5`.
**How to avoid:** Create a new project-local switch with OCaml 5.4.0 before installing melange.
**Warning signs:** `opam install melange.6.0.1-54` prints conflict messages about ocaml version.

### Pitfall 4: Type Parameter Collision with Declarations
**What goes wrong:** A type parameter named `Metadata` gets resolved as a reference to a declaration named `Metadata`.
**Why it happens:** `is_known_decl` doesn't distinguish type parameters from declarations.
**How to avoid:** Check type parameters FIRST (before `is_known_decl`) in `map_type`. Currently no collisions exist, but this is fragile.
**Warning signs:** Bare uppercase names in generated output where type variables are expected.

### Pitfall 5: Circular Module Dependencies Within a File
**What goes wrong:** Topological sort encounters a cycle between two declarations that mutually reference each other.
**Why it happens:** Some IR declarations have mutual type references.
**How to avoid:** Detect cycles during topological sort. Break them by emitting abstract type stubs before the cycle participants.
**Warning signs:** Infinite loop or exception during sort phase.

### Pitfall 6: dune-project Lang Version
**What goes wrong:** `(using melange 0.1)` is rejected because `(lang dune 3.16)` predates melange plugin support at the level required by melange 6.0.1.
**Why it happens:** melange 6.0.1-54 requires `dune >= 3.18`.
**How to avoid:** Bump `(lang dune 3.16)` to `(lang dune 3.18)` in `dune-project`.
**Warning signs:** dune error about unsupported stanza or missing plugin.

## Code Examples

### Cross-Module Qualification (transform.ml)
```ocaml
(* Source: project analysis *)

(* Add to resolve.ml *)
let file_module_of env name =
  match Hashtbl.find_opt env.decls name with
  | Some info -> Some (String.capitalize_ascii info.module_name)
  | None -> None

(* Modified map_type signature *)
let rec map_type env ~current_module ~type_params (t : Ir.typ) : ocaml_type =
  match t with
  (* Check type params FIRST *)
  | Ref { name; args = [] }
    when List.exists (fun (tp : Ir.type_param_def) -> tp.tp_name = name) type_params ->
    Tvar ("'" ^ String.lowercase_ascii name)
  (* Then known declarations with cross-module qualification *)
  | Ref { name; args } when Resolve.is_known_decl env name ->
    let cur_file_mod = String.capitalize_ascii current_module in
    let decl_file_mod =
      match Resolve.file_module_of env name with
      | Some m -> m
      | None -> cur_file_mod  (* fallback: assume same module *)
    in
    let prefix =
      if decl_file_mod <> cur_file_mod then decl_file_mod ^ "."
      else ""
    in
    let base = Tname (prefix ^ Naming.module_name_of name ^ ".t") in
    if args = [] then base
    else Tapply (base, List.map (map_type env ~current_module ~type_params) args)
  | ...
```

### Topological Sort for Module Ordering
```ocaml
(* Source: standard topological sort pattern *)

(* Build adjacency list from declarations *)
let build_dep_graph (decls : Ir.decl list) local_names =
  List.map
    (fun d ->
       let refs = (* collect all type name refs from d's members and type *) in
       let local_deps = List.filter (fun r -> List.mem r local_names) refs in
       (d.d_name, local_deps))
    decls

(* Kahn's algorithm or DFS-based topological sort *)
let topo_sort decls =
  let graph = build_dep_graph decls (List.map (fun d -> d.d_name) decls) in
  (* ... standard topo sort returning sorted decl list ... *)
```

### Bind Module Construction (transform.ml)
```ocaml
(* Source: binding_ast.ml types + emit.ml pp_bind_module *)

(* Extend classify_union to detect finite input unions *)
let classify_union_with_position ~position members =
  let non_null = List.filter (fun m ->
    match m with
    | Ref { name = "null" | "undefined"; _ } -> false
    | _ -> true) members
  in
  let has_null = List.length non_null < List.length members in
  if has_null && List.length non_null = 1 then
    `Nullable (List.hd non_null)
  else if position = `Input && List.length non_null >= 2 && List.length non_null <= 5 then
    `Bind (non_null, has_null)
  else
    `Fallback

(* Build Bind module from classified union *)
let build_bind_module env ~current_module ~type_params members has_null =
  let constructors = List.map (fun m ->
    let typ = map_type env ~current_module ~type_params m in
    let name = bind_constructor_name m in
    (name, typ)
  ) members in
  Bind { bm_name = "Bind"; bm_constructors = constructors; bm_has_null = has_null }
```

### Inheritance Alias (transform.ml)
```ocaml
(* Source: project analysis *)

let transform_class env ~current_module (d : decl) : ocaml_module =
  let type_item =
    match d.d_extends with
    | [ Ref { name; _ } ]
      when Resolve.is_known_decl env name
           && name <> "Error"
           && name <> "Record" ->
      let target = map_type env ~current_module ~type_params:d.d_type_params
        (Ref { name; args = [] }) in
      Type (Alias { name = "t"; target; doc = d.d_doc })
    | _ ->
      Type (Abstract { name = "t"; doc = d.d_doc })
  in
  ...
```

### Test File Generation Pattern
```ocaml
(* Source: project convention -- parallel test directory *)

(* For each output file like streams.ml, emit streams_test.ml *)
(* The test file just needs to reference types to trigger type-checking *)

(* Example generated test: streams_test.ml *)
(*
  open Cf_workers_bindings.Streams

  let _readable : Readable_Stream.t -> bool =
    fun s -> Readable_Stream.locked s

  let _writable : Writable_Stream.t -> bool =
    fun s -> Writable_Stream.locked s
*)
```

### dune-project Changes
```scheme
;; Before
(lang dune 3.16)

;; After
(lang dune 3.18)
(using melange 0.1)
```

### Bindings Library dune Stanza
```scheme
;; output/cf_workers_bindings/dune
(library
 (name cf_workers_bindings)
 (modes melange))
```

### Test Suite dune Stanza
```scheme
;; output/cf_workers_bindings_test/dune
(melange.emit
 (target test_output)
 (libraries cf_workers_bindings))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `(library (modes melange))` alone | `melange.emit` stanza required to trigger compilation | Always (dune design) | Must have an emit stanza for compile-check |
| OCaml 5.2 + melange 5.x | OCaml 5.4 + melange 6.0.1 | melange 6.0.1 release | New switch required |
| `(lang dune 3.16)` | `(lang dune 3.18)` minimum | melange 6.0.1 | dune-project update needed |

## Open Questions

1. **Topological sort cycle handling**
   - What we know: Cycles likely exist in complex files (e.g., `ai.ml` has many interrelated declarations)
   - What's unclear: Exact number and nature of cycles; whether abstract stubs or `module rec` is better
   - Recommendation: Implement topo sort, detect cycles, emit abstract forward stubs for cycle breakers. Log warnings for cycles found.

2. **Bind module naming for complex unions**
   - What we know: Simple cases like `string | URL` map cleanly to `of_string`/`of_url`
   - What's unclear: How to name constructors for unions like `ReadableStream | ArrayBuffer | ArrayBufferView | string | Blob | null` (5 members + null)
   - Recommendation: Use `of_` prefix + snake_case of type name. For `ArrayBufferView`, use `of_array_buffer_view`. Accept long names.

3. **Whether codegen test should exercise externals or just reference types**
   - What we know: TEST-01 says "calls each external with correctly-typed arguments"
   - What's unclear: Whether Melange compile-check requires actual call expressions or if type annotations suffice
   - Recommendation: Emit type-annotated `let` bindings that reference the external. This proves the type resolves without needing to construct values of every type. E.g., `let _f : string -> Readable_Stream.t -> string option Js.Promise.t = Kv_Namespace.get`

4. **opam switch migration**
   - What we know: Current switch is OCaml 5.2, melange needs 5.4
   - What's unclear: Whether to recreate the project-local switch or create a parallel one
   - Recommendation: Recreate the project-local switch (`opam switch create . 5.4.0 --deps-only`). This replaces `_opam/` in place. The codegen tool itself has no OCaml 5.4-incompatible code.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| OCaml | Everything | Needs upgrade | 5.2.0 (need 5.4.0) | Create new switch |
| Melange | Bindings compilation | Not installed | Need 6.0.1-54 | Install via opam |
| dune | Build system | Available | 3.21.1 | -- (sufficient) |
| opam | Package management | Available | -- | -- |
| Node.js | Extraction only (not needed this phase) | Available | -- | -- |

**Missing dependencies with no fallback:**
- OCaml 5.4.0 switch must be created (cannot compile melange bindings with 5.2)
- melange 6.0.1-54 must be installed (no alternative for Melange compilation)

**Missing dependencies with fallback:**
- None -- both missing deps must be installed

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | alcotest 1.9.1 (codegen unit tests) + melange.emit compilation (binding validation) |
| Config file | `test/dune` (existing), `output/cf_workers_bindings_test/dune` (Wave 0) |
| Quick run command | `dune build @melange` |
| Full suite command | `dune build @melange && dune runtest` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BIND-01 | Cross-module types resolve, stream types qualified | compilation | `dune build @melange` | No -- Wave 0 |
| BIND-02 | Bind modules emitted for finite input unions | compilation + unit | `dune build @melange && dune runtest` | No -- Wave 0 |
| BIND-03 | Inheritance aliases emitted for extends chains | compilation | `dune build @melange` | No -- Wave 0 |
| PKG-01 | dune stanza active, melange plugin enabled | compilation | `dune build @melange` | No -- Wave 0 |
| TEST-01 | Test suite generated alongside bindings | compilation | `dune build @melange` (triggers test compilation) | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `dune build @melange` (fast -- only compiles melange targets)
- **Per wave merge:** `dune build @melange && dune runtest`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `output/cf_workers_bindings/dune` -- uncomment library stanza
- [ ] `output/cf_workers_bindings_test/dune` -- melange.emit stanza for compile tests
- [ ] `output/cf_workers_bindings_test/*_test.ml` -- generated test files (43 files)
- [ ] `dune-project` -- `(using melange 0.1)` and lang bump to 3.18
- [ ] `spiceflare.opam` -- melange dependency addition
- [ ] New opam switch: `opam switch create . 5.4.0 --deps-only && opam install melange.6.0.1-54`

## Sources

### Primary (HIGH confidence)
- Project source code analysis: `lib/transform.ml`, `lib/binding_ast.ml`, `lib/emit.ml`, `lib/resolve.ml`, `lib/ir.ml`, `lib/naming.ml`
- `data/workers-ir.json` direct analysis via Python scripts
- `opam info melange.6.0.1-54` -- verified dependencies
- `opam switch list-available` -- verified OCaml 5.4.0 availability
- Generated output analysis: `output/cf_workers_bindings/*.ml` (43 files, ~10k lines)

### Secondary (MEDIUM confidence)
- [Melange build system documentation](https://melange.re/unstable/build-system.html) -- melange.emit stanza behavior, library modes
- [Dune Melange documentation](https://dune.readthedocs.io/en/stable/melange.html) -- `(using melange 0.1)` plugin
- [Melange GitHub](https://github.com/melange-re/melange) -- version history

### Tertiary (LOW confidence)
- None -- all findings verified against project source or official package metadata

## Project Constraints (from CLAUDE.md)

### Actionable Directives
- **Tech stack**: OCaml >= 5.2, Node.js >= 18, dune >= 3.16, Melange for generated output (NOTE: PKG-05 overrides to OCaml >= 5.4)
- **Naming**: `spiceflare` opam package = published bindings; `spiceflare-codegen` = generator
- **No runtime**: Both packages are offline tools/artifacts
- **Code style**: ocamlformat 0.27.0, profile default, 2-space indent
- **Conventions**: snake_case modules, `open Ir` and `open Binding_ast` at top of transform files
- **Format margin**: 90 characters (`Format.pp_set_margin fmt 90`)
- **GSD Workflow**: Do not make direct repo edits outside a GSD workflow unless user explicitly asks

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- versions verified against opam registry
- Architecture: HIGH -- all fixes derived from direct source code analysis and IR data inspection
- Pitfalls: HIGH -- all based on concrete findings (7 module name mismatches, forward refs counted, etc.)

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (stable domain -- OCaml/Melange/dune ecosystem moves slowly)
