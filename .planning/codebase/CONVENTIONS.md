# Code Conventions

**Analysis Date:** 2026-03-26

## Naming Conventions

**Files:**
- Snake_case module stems: `binding_ast.ml`, `ir_parse.ml`, `transform.ml`
- File names match module names exactly (dune default)
- No `.mli` interface files — all modules expose their full signature

**Functions:**
- Public functions: `snake_case` — `to_snake_case`, `escape_keyword`, `parse_file`, `emit_all`
- Private helpers: `snake_case` with contextual prefix — `str_field`, `bool_field`, `list_field`
- Predicate helpers use `is_` prefix — `is_upper`, `is_lower`, `is_known_decl`, `is_input_interface`
- Constructor helpers use descriptive names — `labelled_param`, `optional_param`, `positional_param`
- Setter bindings use `set_` prefix — `set_<property_name>` (generated output convention)

**Types:**
- Variant constructors: `PascalCase` — `Ref`, `Array`, `Union`, `Tname`, `Tapply`, `Mel_new`, `Mel_send`
- Record field names use module-specific short prefixes:
  - `ap_` for `arrow_param` fields: `ap_label`, `ap_type`, `ap_mel_this`
  - `e_` for `external_decl` fields: `e_name`, `e_js_name`, `e_type`, `e_attrs`, `e_doc`
  - `rf_` for `record_field` fields: `rf_name`, `rf_type`, `rf_mel_as`, `rf_optional`
  - `m_` for `ocaml_module` fields: `m_name`, `m_items`
  - `of_` for `output_file` fields: `of_filename`, `of_header`, `of_modules`, `of_toplevel`
  - `d_` for `decl` fields: `d_kind`, `d_name`, `d_members`, etc.
  - `mg_` for `module_group` fields: `mg_name`, `mg_declarations`
  - `p_` for `param` fields: `p_name`, `p_type`, `p_optional`, `p_rest`
  - `tp_` for `type_param_def` fields: `tp_name`, `tp_constraint`, `tp_default`
  - `mo_` for `method_overload` fields: `mo_type_params`, `mo_params`, `mo_return_type`
  - `bm_` for `bind_module` fields: `bm_name`, `bm_constructors`, `bm_has_null`
- Type aliases lowercase: `usage`, `env`, `label`
- Variant constructors for classifications use backtick polymorphic variants: `` `Nullable ``, `` `Fallback ``

**Variables:**
- Let bindings: `snake_case` — `ir_path`, `output_dir`, `kv_ns`
- Loop/iteration variables: short names — `i`, `c`, `m`, `d`, `p`, `ov`
- Accumulator variables: `acc`, `buf`
- Mutable refs: descriptive noun — `modules`, `toplevel`, `found`

**Modules:**
- Library is `spiceflare_lib` (dune library name)
- Called as `SpiceFlare_lib.Module_name.function` from the executable
- `module J = Yojson.Safe.Util` — short alias for heavily-used modules

## Code Style

**Formatter:**
- `ocamlformat` version `0.27.0`, profile `default`
- Config at `.ocamlformat`

**Indentation:**
- 2 spaces (ocamlformat default profile)
- Dune files use 1-space indentation

**Line length:**
- `Format.pp_set_margin fmt 90` used in both `emit.ml` and `test_all.ml`, establishing 90 as the project line width

**Section separators:**
- Horizontal rule comments divide logical sections within a file:
  ```ocaml
  (* ── Section name ───────────────────────────────────────────────────── *)
  ```
- Used consistently in `transform.ml`, `emit.ml`, `resolve.ml`

**Module opens:**
- `open Ir` and `open Binding_ast` used at top of files that operate extensively on those types
- Avoids qualifying every variant/record constructor
- Short local alias `module J = Yojson.Safe.Util` used in `ir_parse.ml`

## Common Patterns

**Pipeline / let-binding operator:**
- `let ( let* ) = Result.bind` defined locally in `ir_parse.ml` for monadic error threading (though currently used sparingly — JSON defaults to empty on missing fields rather than propagating errors)

**Pipe operator for transforms:**
```ocaml
name |> to_snake_case |> escape_keyword
```
Used in `naming.ml` for chained string transforms.

**match with default catch-all:**
Fallback branches always document what they do:
```ocaml
| other ->
  Printf.eprintf "Warning: unknown type kind %S, treating as any\n" other;
  Ref { name = "any"; args = [] }
```

**Accumulator pattern with `ref`:**
Used in `transform.ml` where the output lists are built imperatively over a `List.iter`:
```ocaml
let modules = ref [] in
let toplevel = ref [] in
List.iter (fun d -> ... modules := m :: !modules; ...) decls;
{ of_modules = List.rev !modules; of_toplevel = List.rev !toplevel; ... }
```

**List.concat_map** for flat-mapping over member lists:
```ocaml
List.concat_map (transform_member env ~self_type ~source_module) d.d_members
```

**Hashtbl for O(1) lookups:**
Keyword set and declaration registry both use `Hashtbl.t` with `Hashtbl.create`, `Hashtbl.replace`, `Hashtbl.mem`, `Hashtbl.find_opt`.

**Type constructor helpers at module top:**
Short let-bound aliases for frequently constructed types:
```ocaml
let unit_t = Tunit
let string_t = Tname "string"
let float_t = Tname "float"
let promise_t inner = Tapply (Tname "Js.Promise.t", [ inner ])
```

**Format module for pretty-printing:**
`emit.ml` uses `Format.fprintf` aliased to `pp`, with box annotations (`@[<hv 2>`, `@[<v 0>`) for line-break hints. Line width set to 90.

**Mutable record fields for staged analysis:**
`resolve.ml` uses `mutable usage : usage` on `decl_info` to allow two-pass classification without threading state:
```ocaml
type decl_info = { decl : decl; mutable usage : usage; module_name : string }
```

## Error Handling

**Approach:** Defensive defaults, not exceptions.

**JSON parsing:** Missing or wrong-typed fields default to empty strings, `false`, or `[]` via helper functions in `ir_parse.ml`:
```ocaml
let str_field key json = match J.member key json with `String s -> s | _ -> ""
let bool_field key json = match J.member key json with `Bool b -> b | _ -> false
let list_field key json = match J.member key json with `List l -> l | _ -> []
```

**Unknown enum values:** `Printf.eprintf` warning + safe fallback:
```ocaml
| other ->
  Printf.eprintf "Warning: unknown type kind %S, treating as any\n" other;
  Ref { name = "any"; args = [] }
```

**CLI argument errors:** Early exit with usage message to stderr:
```ocaml
if argc < 3 then begin
  Printf.eprintf "Usage: %s <workers-ir.json> <output-dir>\n" Sys.argv.(0);
  exit 1
end
```

**No Result/Option propagation in the happy path:** The pipeline (`parse → resolve → transform → emit`) does not use `Result.t` for the main flow — invalid input produces degraded output with warnings rather than aborting.

**Option handling:** `Hashtbl.find_opt` and `List.find_map` used consistently; `None` cases handled inline at call sites.

## Documentation Style

**Module-level doc comments:**
Every `.ml` file opens with an `(** ... *)` doc comment describing the module's purpose and approach. Examples:
- `ir.ml`: `(** Input AST types mirroring our custom workers-ir.json schema. ... *)`
- `naming.ml`: `(** Name conversion: camelCase/PascalCase to snake_case, keyword escaping. ... *)`
- `emit.ml`: `(** Pretty-print Binding AST as .ml source files. Uses the Format module for readable output with proper line breaking. *)`

**Function doc comments:**
Significant public functions have `(** ... *)` doc comments. Private helpers omit them unless the algorithm is non-obvious:
```ocaml
(** Convert a camelCase or PascalCase identifier to snake_case.

    The algorithm inserts underscores at case transitions:
    - Before an uppercase letter that follows a lowercase letter or digit
    - Before the last letter of an uppercase run that is followed by lowercase ... *)
```

**Type variant doc comments:**
Variants annotated with inline `(** ... *)` comments on the same line:
```ocaml
| Tname of string  (** e.g., "string", "float", "t", "Kv.t" *)
| Tapply of ocaml_type * ocaml_type list  (** e.g., string Js.Promise.t *)
| Tvar of string  (** 'a, 'b *)
```

**Record field annotations:**
Same inline style for record fields:
```ocaml
e_name : string;  (** OCaml name *)
e_js_name : string;  (** JS string literal *)
```

**Inline algorithmic comments:**
Short `(* ... *)` comments explain non-obvious branches:
```ocaml
(* Shorthand: bare string means a simple named reference *)
(* Static methods: no receiver *)
(* Instance methods: receiver last with [@mel.this] *)
(* Constructors handled separately *)
```

**No README** at project root — development instructions live in `DEVELOP.md`.

**Design notes** live in `_notes/` (e.g., `_notes/cf-workers-melange-codegen.md`) and are not committed as public documentation.
