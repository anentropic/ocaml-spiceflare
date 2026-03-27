# Phase 3: CI and Testing - Research

**Researched:** 2026-03-27
**Domain:** GitHub Actions CI/CD, OCaml/Melange build verification, branch protection
**Confidence:** HIGH

## Summary

Phase 3 updates two existing GitHub Actions workflows (`.github/workflows/ci.yml` and `.github/workflows/update-types.yml`) and adds branch protection for the main branch. The existing CI is a single-job workflow targeting OCaml 5.2 with a monolithic `dune build`. It needs to become two parallel jobs (one per package) targeting OCaml 5.4, with an additional `@melange` alias build step. The update-types workflow needs its binary reference changed from `spiceflare` to `spiceflare-codegen` and must regenerate the compile-checking test suite alongside the bindings.

This is a well-scoped infrastructure phase. The technologies involved (GitHub Actions YAML, `gh api` for branch protection, `setup-ocaml` action, dune package builds) are stable and well-documented. The main risk is getting the `gh api` branch protection call exactly right and ensuring the job names in the matrix match what gets configured as required status checks.

**Primary recommendation:** Use a matrix strategy with `package: [spiceflare, spiceflare-codegen]` to create two parallel CI jobs, add `dune build @melange` as a separate step in the spiceflare job, and configure branch protection via `gh api PUT` after the first successful workflow run establishes the check context names.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TEST-02 | CI runs `dune build -p spiceflare` and `dune build -p spiceflare-codegen` on OCaml 5.4 in GitHub Actions, and both pass | Matrix strategy with `setup-ocaml@v3` + `ocaml-compiler: 5.4.x`; two parallel jobs via `strategy.matrix.package` |
| REL-02 | `update-types.yml` CI workflow updated for two-package structure, regenerates bindings and test suite, opens PR on API changes | Binary rename `spiceflare` -> `spiceflare-codegen`, add test suite regeneration step, update `peter-evans/create-pull-request` to v8 |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Tech stack**: OCaml >= 5.4, Node.js >= 18, dune >= 3.18, Melange >= 6.0.1
- **Naming**: `spiceflare` = bindings package, `spiceflare-codegen` = generator tool
- **Binary name**: `spiceflare-codegen` (set via `public_name` in `bin/dune`)
- **Two packages**: `spiceflare.opam` (melange bindings) and `spiceflare-codegen.opam` (generator) in same repo
- **ocamlformat**: version 0.27.0, profile default (not relevant to CI YAML but noted)
- **Test framework**: alcotest for codegen unit tests (`test/dune` with `(package spiceflare-codegen)`)
- **Melange test suite**: `output/cf_workers_bindings_test/` with `melange.emit` stanza tagged `(package spiceflare)`

## Standard Stack

### Core (GitHub Actions)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `ocaml/setup-ocaml` | v3 (latest v3.5.1) | Install OCaml compiler and opam in CI | Official OCaml GitHub Action; tracks latest stable opam |
| `actions/checkout` | v4 | Checkout repository | Standard GH Action |
| `actions/setup-node` | v4 | Install Node.js for extraction stage | Standard GH Action |
| `peter-evans/create-pull-request` | v8 (latest v8.1.0) | Create automated PRs in update-types workflow | De facto standard for automated PR creation; existing workflow uses v6, should upgrade |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `dune-cache: true` | setup-ocaml input | Cache dune build artifacts between CI runs | Always enable -- speeds up incremental builds |
| `gh api` | gh CLI 2.x | Set branch protection via REST API | One-time setup step after first CI run |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Matrix strategy (2 parallel jobs) | Separate named jobs | Matrix is cleaner YAML, but separate jobs give more descriptive names in the checks UI. **Use matrix** per user decision for parallelism. |
| `peter-evans/create-pull-request@v8` | `gh pr create` in workflow | peter-evans action handles git add/commit/push + PR atomically; `gh pr create` would require manual git operations. Keep peter-evans. |
| Legacy branch protection API | Repository rulesets API | Legacy API is simpler for single-branch protection. Rulesets are newer but more complex. **Use legacy API** -- it's sufficient for requiring status checks on main. |

## Architecture Patterns

### CI Workflow Structure (ci.yml)

```yaml
name: CI
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        package: [spiceflare, spiceflare-codegen]
    steps:
      - uses: actions/checkout@v4
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.4.x
          dune-cache: true
      - run: opam install . --deps-only --with-test
      - run: opam exec -- dune build -p ${{ matrix.package }}
      - run: opam exec -- dune runtest -p ${{ matrix.package }}

  melange-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.4.x
          dune-cache: true
      - run: opam install . --deps-only --with-test
      - run: opam exec -- dune build @melange
```

**Key design decisions:**

1. **`fail-fast: false`** -- Both package builds run to completion even if one fails, so you see all failures at once.

2. **Separate `melange-check` job** -- The user decision requires `dune build @melange` as an explicit step. This builds all `melange.emit` stanzas (the bindings library AND the test suite). It cannot be inside the matrix because `@melange` is a global alias, not package-scoped.

3. **`opam install . --deps-only --with-test`** -- In a multi-package repo, this installs deps for ALL packages. With opam 2.2+ (shipped by setup-ocaml@v3), this works correctly. The melange-check job needs both packages' deps since `@melange` touches the bindings (spiceflare's deps) and building the codegen is needed to have generated the test files.

4. **`ocaml-compiler: 5.4.x`** -- Resolves to latest 5.4 patch (currently 5.4.0; 5.4.1 if/when released). The `.x` suffix lets setup-ocaml pick the latest patch.

### Update-Types Workflow Structure (key changes)

The existing workflow needs three targeted changes:

1. **OCaml version**: `5.2.x` -> `5.4.x`
2. **Binary reference**: `dune exec spiceflare` -> `dune exec spiceflare-codegen`
3. **Test suite regeneration**: After regenerating bindings, also regenerate the test suite into `output/cf_workers_bindings_test/`
4. **PR commit paths**: Include `output/cf_workers_bindings_test/` in the PR diff
5. **peter-evans action**: `@v6` -> `@v8`

```yaml
# In the "Regenerate bindings" step, change:
- run: |
    opam exec -- dune build
    opam exec -- dune exec spiceflare-codegen -- \
      data/workers-ir.json output/cf_workers_bindings/
# The codegen binary now emits both bindings AND test suite
# (TEST-01 from Phase 1 makes codegen emit test files alongside bindings)
```

### Branch Protection via gh CLI

```bash
gh api -X PUT /repos/{owner}/{repo}/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      {"context": "build (spiceflare)"},
      {"context": "build (spiceflare-codegen)"},
      {"context": "melange-check"}
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

**Critical caveat:** The `context` names in `checks` must match the actual job names as they appear in GitHub's status checks. For a matrix job named `build` with `matrix.package`, GitHub creates check names like `build (spiceflare)` and `build (spiceflare-codegen)`. The separate `melange-check` job appears as `melange-check`. These names must be verified after the first CI run completes -- they may be prefixed with the workflow name (e.g., `CI / build (spiceflare)`).

**Note:** This command requires admin access to the repository. The `gh` CLI must be authenticated with a token that has `repo` scope (or `admin:repo` for organization repos).

### Anti-Patterns to Avoid

- **Single monolithic CI job**: Masks which package failed. User explicitly decided against this.
- **`opam install ./spiceflare.opam --deps-only` per job**: Installs only one package's deps. For the matrix approach, `opam install . --deps-only` is needed since `@melange` requires both packages' deps.
- **Hardcoding OCaml version as `5.4.0`**: Use `5.4.x` to auto-resolve to latest patch release.
- **Skipping `--with-test` on deps install**: The codegen unit tests (alcotest) need their test deps installed.
- **Setting `enforce_admins: true` on branch protection**: Would block the repo owner from merging without checks, which is overly restrictive for a personal project.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Automated PR on API changes | Custom git + gh CLI scripting | `peter-evans/create-pull-request@v8` | Handles dirty working tree, branch management, force-push of updates to existing PR branch atomically |
| OCaml/opam CI setup | Manual opam bootstrap script | `ocaml/setup-ocaml@v3` | Handles opam init, compiler install, depext, caching; maintained by OCaml team |
| Branch protection | GitHub UI manual configuration | `gh api PUT` one-liner | Reproducible, scriptable, documented in plan |

## Common Pitfalls

### Pitfall 1: opam install . in multi-package repo

**What goes wrong:** `opam install . --deps-only` silently does nothing in opam < 2.2 when multiple .opam files are present.
**Why it happens:** Bug in opam 2.1 directory resolution (fixed in 2.2 via PR #5236).
**How to avoid:** `setup-ocaml@v3` ships opam 2.2+. No action needed -- but if debugging CI deps issues, check opam version first.
**Warning signs:** CI step says "Nothing to do" when installing deps.

### Pitfall 2: Branch protection context names

**What goes wrong:** Required status check names don't match the actual check names, so PRs can never be merged (or checks are never required).
**Why it happens:** GitHub prefixes matrix job names differently depending on workflow name and job structure. The check context might be `build (spiceflare)` or `CI / build (spiceflare)` depending on configuration.
**How to avoid:** Run the CI workflow once first, then inspect the actual check names in the GitHub UI or via `gh api /repos/{owner}/{repo}/commits/{sha}/check-runs`. Set branch protection only after confirming the exact context strings.
**Warning signs:** PR shows "Waiting for status to be reported" indefinitely.

### Pitfall 3: Melange dep resolution in CI

**What goes wrong:** `opam install` fails to resolve melange because the version constraint `>= 6.0.1` doesn't match any package named `melange.6.0.1`.
**Why it happens:** Melange packages have OCaml-version suffixes (e.g., `melange.6.0.1-54` for OCaml 5.4). The opam solver resolves `melange >= 6.0.1` correctly because `6.0.1-54` satisfies `>= 6.0.1` (opam version ordering treats `-54` as a pre-release-style suffix that sorts after `6.0.1`).
**How to avoid:** This should work automatically. If it doesn't, the constraint in dune-project may need to be `melange >= 6.0.1-54`.
**Warning signs:** opam solver says "No solution found" for melange.

### Pitfall 4: dune build @melange scope

**What goes wrong:** `dune build @melange` builds ALL melange.emit stanzas in the entire repo, not just one package's.
**Why it happens:** `@melange` is a global alias, not package-scoped.
**How to avoid:** This is actually the desired behavior -- it builds both the bindings library and the compile-checking test suite. But be aware it's not equivalent to `dune build -p spiceflare`.
**Warning signs:** None -- this is expected behavior.

### Pitfall 5: update-types workflow binary name

**What goes wrong:** `dune exec spiceflare` fails because the binary is now named `spiceflare-codegen`.
**Why it happens:** Phase 2 renamed the binary via `(public_name spiceflare-codegen)` in `bin/dune`.
**How to avoid:** Update the workflow to use `dune exec spiceflare-codegen`.
**Warning signs:** Step fails with "Error: Program spiceflare not found".

### Pitfall 6: peter-evans/create-pull-request v6 -> v8 breaking changes

**What goes wrong:** v8 requires Actions Runner v2.327.1+ for Node 24 support.
**Why it happens:** v8 upgraded its Node.js runtime from Node 20 to Node 24.
**How to avoid:** GitHub-hosted `ubuntu-latest` runners already have the required runner version. Only a concern for self-hosted runners.
**Warning signs:** Action fails with Node.js version error on self-hosted runners.

## Code Examples

### Complete ci.yml

```yaml
# Source: Constructed from setup-ocaml docs + project requirements
name: CI

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        package: [spiceflare, spiceflare-codegen]
    steps:
      - uses: actions/checkout@v4
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.4.x
          dune-cache: true
      - run: opam install . --deps-only --with-test
      - run: opam exec -- dune build -p ${{ matrix.package }}
      - run: opam exec -- dune runtest -p ${{ matrix.package }}

  melange-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ocaml/setup-ocaml@v3
        with:
          ocaml-compiler: 5.4.x
          dune-cache: true
      - run: opam install . --deps-only
      - run: opam exec -- dune build @melange
```

### Branch protection gh command

```bash
# Run AFTER first successful CI to verify check context names
# Check names must match exactly -- verify first with:
gh api /repos/{owner}/{repo}/commits/$(git rev-parse HEAD)/check-runs \
  --jq '.check_runs[].name'

# Then set protection:
gh api -X PUT /repos/{owner}/{repo}/branches/main/protection \
  --input - <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      {"context": "build (spiceflare)"},
      {"context": "build (spiceflare-codegen)"},
      {"context": "melange-check"}
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
EOF
```

### update-types.yml regeneration step (changed lines)

```yaml
# Old:
- run: |
    opam exec -- dune build
    opam exec -- dune exec spiceflare -- \
      data/workers-ir.json output/cf_workers_bindings/

# New:
- run: |
    opam exec -- dune build
    opam exec -- dune exec spiceflare-codegen -- \
      data/workers-ir.json output/cf_workers_bindings/
```

Note: The codegen binary already emits the test suite to `output/cf_workers_bindings_test/` as part of its normal operation (Phase 1, TEST-01). No separate regeneration step is needed for the test suite -- it is regenerated as a side effect of running the codegen.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `setup-ocaml@v2` | `setup-ocaml@v3` (v3.5.1) | 2024 | v3 tracks latest stable opam, better caching |
| `peter-evans/create-pull-request@v6` | `@v8` (v8.1.0) | Dec 2024 | Node 24 runtime, better error handling |
| opam 2.1 in CI | opam 2.2+ (via setup-ocaml@v3) | 2024 | Fixes multi-package `install . --deps-only` bug |
| OCaml 5.2.x | OCaml 5.4.x (5.4.0 released Oct 2025) | Oct 2025 | Required by melange 6.0.1-54 |
| `melange.5.x` | `melange.6.0.1-54` | 2025 | OCaml 5.4 support via `-54` suffix |
| Single CI job | Matrix strategy (2 parallel jobs) | This phase | Isolates package build failures |
| No dune-cache | `dune-cache: true` | Available since setup-ocaml@v3 | Faster incremental CI builds |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | GitHub Actions workflows (YAML) + `gh` CLI |
| Config files | `.github/workflows/ci.yml`, `.github/workflows/update-types.yml` |
| Quick run command | `yamllint .github/workflows/*.yml` (syntax) or `cat .github/workflows/ci.yml` (manual review) |
| Full suite command | Push to branch and verify workflow runs pass in GitHub Actions UI |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-02 | CI builds both packages on OCaml 5.4 | smoke (CI run) | `gh workflow run ci.yml` then `gh run list --workflow=ci.yml --limit=1` | Needs update (ci.yml exists but is stale) |
| TEST-02 | Both package builds pass | smoke (CI run) | `gh run view --json jobs --jq '.jobs[].name'` to verify two matrix jobs | Needs update |
| TEST-02 | CI runs on every push | config inspection | Verify `on: [push, pull_request]` in ci.yml | Exists (already configured) |
| REL-02 | update-types workflow uses correct binary name | config inspection | `grep 'spiceflare-codegen' .github/workflows/update-types.yml` | Needs update (currently says `spiceflare`) |
| REL-02 | update-types regenerates test suite | config inspection | Verify `output/cf_workers_bindings_test/` in PR commit paths or add-paths | Needs update |
| REL-02 | update-types opens PR on changes | manual (trigger workflow_dispatch) | `gh workflow run update-types.yml` then check for PR | Exists (peter-evans action configured) |
| SC-03 | Branch protection blocks merge on CI failure | manual | `gh api /repos/{owner}/{repo}/branches/main/protection` to verify rules | Does not exist yet |

### Sampling Rate

- **Per task commit:** Validate YAML syntax locally via inspection; verify `grep` for key strings
- **Per wave merge:** Push branch to trigger CI, verify all jobs pass in GitHub Actions
- **Phase gate:** All three success criteria verified: (1) both package builds pass, (2) update-types workflow correct, (3) branch protection set

### Wave 0 Gaps

- None -- no test framework installation needed. This phase modifies workflow YAML files and runs a `gh api` command. Validation is done by triggering the workflows and inspecting results.

## Open Questions

1. **Exact check context names for branch protection**
   - What we know: Matrix jobs typically appear as `build (spiceflare)` and `build (spiceflare-codegen)`. Separate jobs appear by their job ID.
   - What's unclear: Whether GitHub prefixes with the workflow name (e.g., `CI / build (spiceflare)`)
   - Recommendation: Set branch protection AFTER first successful CI run. Include a verification step in the plan that queries `gh api` to discover actual context names before configuring protection.

2. **opam install . --deps-only in melange-check job**
   - What we know: `dune build @melange` builds all melange.emit stanzas. The bindings library deps (melange) are needed.
   - What's unclear: Whether `opam install . --deps-only` (without `--with-test`) is sufficient, since the test suite's melange.emit has `(package spiceflare)` and tests are a "test" concern.
   - Recommendation: Use `--deps-only` without `--with-test` for the melange-check job. The melange.emit stanza in the test suite directory is not marked as a test -- it's a regular build target attached to the `@melange` alias. It only needs `melange` and `cf_workers_bindings` (both in spiceflare's regular deps).

3. **Remote origin vs. dune-project metadata**
   - What we know: The git remote is `anentropic/ocaml-spiceflare` but dune-project references `paul-j-lucas/spiceflare` in source/homepage/doc fields.
   - What's unclear: Which is the canonical GitHub path for `gh api` calls.
   - Recommendation: Use `{owner}/{repo}` dynamically via `gh api /repos/{owner}/{repo}/...` or use `$GITHUB_REPOSITORY` in workflows. For local `gh` commands, the CLI auto-detects from git remote.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `gh` CLI | Branch protection setup | Yes | 2.88.1 | -- |
| `opam` | CI (via setup-ocaml) | Yes (local) | 2.5.0 | CI uses setup-ocaml which installs opam |
| GitHub Actions | CI/CD | Yes (remote) | -- | -- |
| Node.js | update-types extraction | Yes (local) | v24.14.1 | CI pins Node 22 |

**Missing dependencies with no fallback:** None

**Missing dependencies with fallback:** None -- dune is not installed locally but is available in CI via `opam install . --deps-only` (dune is an implicit dep of all opam packages built with dune).

## Sources

### Primary (HIGH confidence)
- [ocaml/setup-ocaml](https://github.com/ocaml/setup-ocaml) - action.yml inputs, version v3.5.1
- [peter-evans/create-pull-request](https://github.com/peter-evans/create-pull-request/releases) - latest v8.1.0
- [GitHub REST API - Branch Protection](https://docs.github.com/en/rest/branches/branch-protection) - PUT endpoint structure, required fields
- [opam.ocaml.org/packages/melange](https://opam.ocaml.org/packages/melange/) - melange 6.0.1-54 availability, OCaml 5.4 constraint
- [OCaml 5.4.0 release](https://ocaml.org/changelog/2025-10-09-ocaml-540) - release date Oct 2025

### Secondary (MEDIUM confidence)
- [Melange build system docs](https://melange.re/unstable/build-system.html) - @melange alias behavior, melange.emit stanza
- [opam issue #5676](https://github.com/ocaml/opam/issues/5676) - multi-package `install . --deps-only` fix in opam 2.2
- [GitHub CLI manual - gh ruleset check](https://cli.github.com/manual/gh_ruleset_check) - alternative to legacy branch protection

### Tertiary (LOW confidence)
- Branch protection check context naming conventions (inferred from GitHub Actions documentation patterns, needs verification after first CI run)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all components verified against official sources and release pages
- Architecture: HIGH - workflow structure follows established patterns from setup-ocaml examples and existing repo conventions
- Pitfalls: HIGH - multi-package opam issue verified via GitHub issue tracker; melange version suffix verified on opam.ocaml.org; binary rename verified in codebase

**Research date:** 2026-03-27
**Valid until:** 2026-06-27 (90 days -- GitHub Actions and opam ecosystem are stable)
