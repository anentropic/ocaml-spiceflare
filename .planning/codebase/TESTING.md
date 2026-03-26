# Testing

**Analysis Date:** 2026-03-26

## Test Framework

**Runner:** Alcotest >= 1.7 (declared in `dune-project` as `(and :with-test (>= 1.7))`)

**Assertion style:** `Alcotest.(check <testable>) "description" expected actual`

**Run Commands:**
```bash
dune runtest          # Run all tests (also rebuilds if needed)
dune build @runtest   # Equivalent alias used in opam build instructions
```

## Test Organization

**Location:** Single test file `test/test_all.ml` — all tests in one module.

**Dune target:**
```
(test
 (name test_all)
 (libraries spiceflare_lib alcotest))
```

**Test registration:** All suites registered in a single `Alcotest.run` call at the bottom of `test/test_all.ml`:
```ocaml
let () =
  Alcotest.run "spiceflare"
    [
      ("naming",   [ test_case ...; test_case ...; ]);
      ("ir_parse", [ test_case ...; ]);
      ("emit",     [ test_case ...; ]);
    ]
```

**Naming:** Test functions are `test_<what>` — `test_snake_case`, `test_keyword_escape`, `test_parse_minimal`, `test_emit_external`.

**Fixtures directory:** `test/fixtures/` exists but is currently empty — no file-based fixtures are used.

**No snapshot/golden-file tests** are present despite the output being `.ml` text files.

## Test Types

**Unit tests — naming logic (`naming` suite):**
- `test_snake_case`: 17 input/output pairs covering camelCase, PascalCase, acronyms (KV, D1, R2, AI, URL, HTML), edge cases (empty string, single char, all-uppercase runs)
- `test_keyword_escape`: 6 cases — reserved words get `_` suffix, non-keywords pass through
- `test_ocaml_name_of_member`: 3 combined cases (snake_case + escape in one call)
- `test_module_name`: 4 cases verifying PascalCase output with underscore-separated acronym groups

All naming tests use a `List.iter` over `(input, expected)` pairs with `Alcotest.(check string)`.

**Integration test — JSON parsing (`ir_parse` suite):**
- `test_parse_minimal`: Inline JSON string with two module groups (kv + globals), one interface with a method and property, one global function. Asserts on version string, module count, module name, declaration count, and member count. Tests the full `parse_string -> Ir.ir` path without hitting disk.

**Unit test — emitter (`emit` suite):**
- `test_emit_external`: Constructs a `Binding_ast.external_decl` directly and calls `Emit.pp_external`, capturing output into a `Buffer`. Asserts that `[@@mel.send]` and `[@mel.this]` appear in the output using a hand-rolled `contains` substring search (not stdlib — `String.sub` loop).

**No tests exist for:**
- `transform.ml` — the IR-to-binding-AST mapping stage
- `resolve.ml` — type reference resolution and input/output classification
- `emit.ml` beyond the single external declaration test
- Full pipeline (parse → resolve → transform → emit)
- The TypeScript extraction toolchain in `extract/`

## Running Tests

```bash
# One-time setup
opam switch create . 5.2.0
eval $(opam env)
opam install . --deps-only --with-test

# Run tests
dune runtest

# Run with verbose output (alcotest flag)
dune runtest --force   # forces rerun even if nothing changed
```

Tests run as part of the CI pipeline (`.github/workflows/ci.yml`) on every push and pull request via `opam exec -- dune runtest`.

## Coverage

**Well-covered:**
- `naming.ml` — `to_snake_case`, `escape_keyword`, `ocaml_name_of_member`, `module_name_of` all have dedicated test cases with representative edge cases
- `ir_parse.ml` — happy-path JSON parsing through `parse_string`
- `emit.ml` — basic external declaration emission (partial)

**Not covered:**
- `transform.ml` (`lib/transform.ml`) — no tests for class transforms, interface transforms (input/output), type alias transforms, method overload disambiguation, union classification, or global function/variable transforms
- `resolve.ml` (`lib/resolve.ml`) — `classify_usage`, `is_input_interface`, `find_decl`, `get_usage` have no direct tests
- `ir_parse.ml` error paths — unknown type kinds, unknown declaration kinds, malformed JSON fields
- `emit.ml` — record types, bind modules, nested modules, full output file emission
- End-to-end pipeline — no test drives `data/workers-ir.json` through the full pipeline and checks the generated `.ml` output
- `extract/` TypeScript code — no test framework configured in that subdirectory
