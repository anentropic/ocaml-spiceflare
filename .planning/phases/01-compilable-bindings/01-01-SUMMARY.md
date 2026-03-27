---
phase: 01-compilable-bindings
plan: 01
subsystem: codegen
tags: [ocaml, melange, cross-module-refs, type-params, topological-sort]

# Dependency graph
requires: []
provides:
  - "file_module_of helper for cross-module type qualification"
  - "~current_module and ~type_params threading through all map_type callers"
  - "Type parameter priority over is_known_decl in map_type"
  - "DFS-based topological sort for intra-file declaration ordering"
  - "Removal of hardcoded ReadableStream/WritableStream special cases"
affects: [01-02, 01-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cross-module qualification: FileModule.DeclModule.t for inter-file type references"
    - "Type parameter detection before declaration lookup in map_type"
    - "Topological sort of declarations within module groups before transformation"

key-files:
  created:
    - lib/sort.ml
  modified:
    - lib/resolve.ml
    - lib/transform.ml
    - bin/main.ml
    - test/test_all.ml

key-decisions:
  - "Used String.capitalize_ascii for dune file module names (not Naming.module_name_of) to match dune's single-capitalize convention"
  - "Type params checked before is_known_decl to prevent T from resolving as a declaration"
  - "Method-level type_params concatenated with declaration-level type_params for full scope"
  - "Cycles in topological sort broken arbitrarily with stderr warning"

patterns-established:
  - "Cross-module qualification pattern: String.capitalize_ascii current_module compared to Resolve.file_module_of result"
  - "Type parameter threading: ~current_module ~type_params passed through all transform functions"

requirements-completed: [BIND-01]

# Metrics
duration: 7min
completed: 2026-03-27
---

# Phase 01 Plan 01: Compile Blockers Summary

**Cross-module type qualification via file_module_of, type parameter threading through map_type, and DFS topological sort for declaration ordering**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-27T00:33:48Z
- **Completed:** 2026-03-27T00:40:33Z
- **Tasks:** 2
- **Files modified:** 5 (resolve.ml, transform.ml, sort.ml, main.ml, test_all.ml)

## Accomplishments
- Cross-module references now emit fully-qualified paths (e.g. Streams.Readable_Stream.t instead of bare Readable_Stream.t)
- Type parameters checked before declaration lookup, preventing bare uppercase names like R from misresolving
- ReadableStream/WritableStream hardcoded special cases removed in favor of normal cross-module resolution
- Declarations within module groups are topologically sorted before emission, eliminating forward references
- All 6 existing tests pass, dune build succeeds

## Task Commits

Each task was committed atomically:

1. **Task 1: Add file_module_of helper and thread ~current_module + ~type_params** - `f4b1785` (feat)
2. **Task 2: Create sort.ml for topological ordering** - `fee7bbb` (feat)

## Files Created/Modified
- `lib/resolve.ml` - Added file_module_of helper for cross-module file module lookup
- `lib/transform.ml` - Threaded ~current_module and ~type_params through all map_type callers, added cross-module prefix logic, removed hardcoded stream types, integrated topological sort
- `lib/sort.ml` - New module: DFS-based topological sort of declarations within module groups
- `bin/main.ml` - Fixed SpiceFlare_lib -> Spiceflare_lib module reference (pre-existing bug)
- `test/test_all.ml` - Fixed SpiceFlare_lib -> Spiceflare_lib module reference (pre-existing bug)

## Decisions Made
- Used String.capitalize_ascii for dune file module names (not Naming.module_name_of) because dune derives module names by capitalizing only the first letter of the filename stem
- Type params are checked before is_known_decl so generic parameters like T, R, W are emitted as 'a, 'r, 'w rather than being resolved as declarations
- Method-level type_params concatenated with declaration-level type_params (method takes precedence via list ordering) for full generic scope
- Cycles in topological sort broken arbitrarily with a warning to stderr (no OCaml-level workaround for mutual recursion without future `and` module support)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed SpiceFlare_lib module name casing in bin/main.ml and test/test_all.ml**
- **Found during:** Task 1 (build verification)
- **Issue:** Pre-existing bug: dune library name `spiceflare_lib` creates OCaml module `Spiceflare_lib`, but code referenced `SpiceFlare_lib` (capital F and L). Build failed before any of our changes.
- **Fix:** Replaced all `SpiceFlare_lib` with `Spiceflare_lib` in bin/main.ml and test/test_all.ml
- **Files modified:** bin/main.ml, test/test_all.ml
- **Verification:** dune build succeeds, dune runtest passes all 6 tests
- **Committed in:** f4b1785 (Task 1 commit)

**2. [Rule 3 - Blocking] Committed project source files needed for build verification**
- **Found during:** Task 1 (commit step)
- **Issue:** All project source files (lib/*.ml, bin/main.ml, dune-project, etc.) were untracked on the gsd branch -- build verification requires them to be committed
- **Fix:** Included all build-essential source files in Task 1 commit alongside the planned changes
- **Files modified:** dune-project, lib/dune, lib/ir.ml, lib/ir_parse.ml, lib/naming.ml, lib/binding_ast.ml, lib/emit.ml, bin/dune, .ocamlformat, spiceflare.opam, test/dune
- **Verification:** dune build succeeds from clean checkout
- **Committed in:** f4b1785 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both auto-fixes necessary for build to succeed. No scope creep.

## Issues Encountered
None beyond the pre-existing module name casing bug documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Cross-module qualification, type parameter threading, and topological sort are in place
- Plan 01-02 (emit fixes and dune stanza) can proceed -- transform.ml now produces correct qualified paths
- Plan 01-03 (regeneration) can proceed after 01-02 completes

## Self-Check: PASSED

All 6 created/modified files verified present. Both task commits (f4b1785, fee7bbb) verified in git log.

---
*Phase: 01-compilable-bindings*
*Completed: 2026-03-27*
