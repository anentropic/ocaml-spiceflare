# External Integrations

**Analysis Date:** 2026-03-26

## APIs & Services

**Cloudflare Workers Types:**
- Package: `@cloudflare/workers-types` (fetched via `npm pack` during the update pipeline)
- Source: npm registry (https://registry.npmjs.org)
- Purpose: The primary input to the tool — `extract/extract.ts` parses its `index.d.ts` to produce `data/workers-ir.json`
- Not a runtime dependency; consumed only during the Stage 1 extraction pipeline
- Versioned artifact committed to repo at `data/workers-ir.json` (81,978 lines); version is synced into `dune-project` automatically

**No other external APIs are called at runtime.** The OCaml codegen reads only local files (`data/workers-ir.json`) and writes to a local output directory (`output/cf_workers_bindings/`).

## Databases & Storage

- None. All data is file-based:
  - Input IR: `data/workers-ir.json` (committed, diffable)
  - Output bindings: `output/cf_workers_bindings/*.ml` (committed, generated)
  - A local tarball `cloudflare-workers-types-*.tgz` is produced during extraction and not committed

## Authentication & Authorization

- None. No auth is required by the tool itself.
- GitHub Actions workflows use the default `GITHUB_TOKEN` (implicit) via `peter-evans/create-pull-request@v6` for automated PR creation.

## Infrastructure & Deployment

**CI/CD — GitHub Actions:**

`ci.yml` — triggered on every push and pull request:
- Runs on `ubuntu-latest`
- Uses `ocaml/setup-ocaml@v3` to install OCaml 5.2.x and opam
- Steps: `opam install --deps-only --with-test` → `dune build` → `dune runtest` → `dune build @doc`

`update-types.yml` — weekly scheduled job (Mondays 09:17 UTC) + manual dispatch:
- Runs on `ubuntu-latest`
- Uses `actions/setup-node@v4` (Node 22) and `ocaml/setup-ocaml@v3` (OCaml 5.2.x)
- Pipeline: fetch `@cloudflare/workers-types` from npm → extract IR → diff → regenerate bindings → sync version → open PR
- On failure: captures diagnostic context in `.failure/FAILURE.md` and opens a separate failure PR for investigation
- Uses `peter-evans/create-pull-request@v6` for automated PR creation on both success and failure paths
- Automated PRs target branch: `auto/update-workers-types`

**No cloud hosting, no deployment target.** This is a code generation CLI tool; it is not deployed as a service.

## Monitoring & Observability

- No runtime monitoring, error tracking, or metrics services.
- Logging is via OCaml's standard `Format` module and `stderr`/`stdout` in `bin/main.ml`.
- CI pipeline failure diagnostics are captured to `.failure/FAILURE.md` and surfaced as a GitHub PR for human (or Copilot) review.

---

*Integration audit: 2026-03-26*
