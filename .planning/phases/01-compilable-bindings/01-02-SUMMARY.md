---
phase: 01-compilable-bindings
plan: 02
subsystem: codegen
tags: [ocaml, melange, inheritance-aliases, bind-modules, union-types, subtype-polymorphism]

# Dependency graph
requires:
  - phase: 01-compilable-bindings/01
    provides: "Cross-module type qualification, type parameter threading, map_type with ~current_module and ~type_params"
provides:
  - "Alias type_decl variant for single-inheritance type aliasing"
  - "Inheritance alias emission in transform_class and transform_interface"
  - "Bind module generation for heterogeneous 2-5 member input unions"
  - "detect_bind_union and bind_constructor_name helpers"
affects: [01-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inheritance alias: single-extends chains emit type t = Parent.t (excluding Error and Record)"
    - "Bind module detection at call site (transform_method_overload/transform_constructor) rather than in map_type"
    - "Bind constructor naming: of_<snake_case_type_name> derived from union member types"

key-files:
  created: []
  modified:
    - lib/binding_ast.ml
    - lib/emit.ml
    - lib/transform.ml

key-decisions:
  - "Alias emission excludes extends Error (maps to Js.Exn.t) and extends Record (TS utility type)"
  - "Bind detection happens at parameter transform sites, not inside map_type -- keeps map_type position-agnostic"
  - "Bind module names derived from parameter name: capitalize(snake_case(param_name)) + _Bind suffix"
  - "Interfaces with own fields keep Record type even when extending a parent (structural, not nominal)"

patterns-established:
  - "Inheritance alias pattern: check d.d_extends for single Ref with no args, guard against Error/Record"
  - "Bind module emission pattern: detect_bind_union at param sites, emit Bind items before External items"

requirements-completed: [BIND-02, BIND-03]

# Metrics
duration: 4min
completed: 2026-03-27
---

# Phase 01 Plan 02: Codegen Enhancements Summary

**Inheritance type aliases for single-extends class/interface chains and Bind module generation with typed smart constructors for 2-5 member heterogeneous input unions**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-27T00:43:43Z
- **Completed:** 2026-03-27T00:47:50Z
- **Tasks:** 2
- **Files modified:** 3 (binding_ast.ml, emit.ml, transform.ml)

## Accomplishments
- Added Alias variant to type_decl enabling `type t = Parent_Module.t` for single-inheritance chains
- Class and interface transforms now detect single-extends parents and emit aliases (excluding Error and Record parents)
- Bind module generation for heterogeneous input union parameters (2-5 concrete members) with typed smart constructors
- Both method overloads and constructors detect and emit Bind modules for union parameters
- All 6 existing tests pass, dune build succeeds

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Alias type_decl variant and implement inheritance alias emission** - `671e7ca` (feat)
2. **Task 2: Implement Bind module generation for heterogeneous input unions** - `7fb9509` (feat)

## Files Created/Modified
- `lib/binding_ast.ml` - Added Alias variant to type_decl with name, target, doc fields
- `lib/emit.ml` - Added Alias case to pp_type_decl (prints `type t = <target>` for aliases)
- `lib/transform.ml` - Added inheritance alias logic to transform_class, transform_interface_input, transform_interface_output; added detect_bind_union, bind_constructor_name helpers; updated transform_method_overload to return bind_module list; updated transform_constructor and transform_member to emit Bind items

## Decisions Made
- Alias emission excludes `extends Error` (Error maps to Js.Exn.t, not a bindable parent) and `extends Record` (TS utility type, not a real parent)
- Bind detection happens at parameter transform sites (transform_method_overload, transform_constructor), not inside map_type -- this keeps map_type position-agnostic and avoids needing a ~position parameter
- Bind module names are derived from the parameter name: `capitalize(snake_case(param_name)) + "_Bind"` suffix
- Interfaces with their own fields keep the Record type even when extending a parent (structural typing, not nominal)
- Input interfaces with no own members that extend a single parent emit Alias instead of mel.obj

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Alias variant and Bind module generation are in place
- Plan 01-03 (regeneration and compile check) can proceed
- transform.ml now handles inheritance aliasing and input union Bind modules

## Self-Check: PASSED

All 3 modified files verified present. Both task commits (671e7ca, 7fb9509) verified in git log. SUMMARY.md exists at expected path.

---
*Phase: 01-compilable-bindings*
*Completed: 2026-03-27*
