---
phase: 03-ci-and-testing
plan: 02
subsystem: ci
tags: [github-actions, branch-protection, required-status-checks]
dependency_graph:
  requires: [03-01]
  provides: []
  affects: []
tech_stack:
  added: []
  patterns: []
key_files:
  created: []
  modified: []
decisions:
  - Branch protection API call deferred -- private repo requires GitHub Pro or public visibility
metrics:
  duration: "3m"
  completed: "2026-03-27"
  tasks_completed: 1
  files_modified: 0
---

# Phase 03 Plan 02: Branch Protection Summary

Branch protection configuration attempted but blocked by GitHub plan restriction (private repo + free tier). Command documented for when repo becomes public or account upgrades.

## What Was Done

### Task 1: Set branch protection via gh api

**Outcome: Blocked by GitHub plan restriction.**

The `gh api -X PUT /repos/anentropic/ocaml-spiceflare/branches/main/protection` call returned HTTP 403:

```
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature."}
```

Repository is currently private (`visibility: PRIVATE`). Branch protection on private repositories requires either:
- GitHub Pro (or Team/Enterprise) account, or
- Making the repository public

**Command to run once the repo is public or the account is upgraded:**

```bash
gh api -X PUT /repos/anentropic/ocaml-spiceflare/branches/main/protection \
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

**Verify with:**

```bash
gh api /repos/anentropic/ocaml-spiceflare/branches/main/protection \
  --jq '{strict: .required_status_checks.strict, checks: [.required_status_checks.checks[].context], enforce_admins: .enforce_admins.enabled}'
```

Expected output once set:
```json
{
  "strict": true,
  "checks": ["build (spiceflare)", "build (spiceflare-codegen)", "melange-check"],
  "enforce_admins": false
}
```

**Note on context names:** The check context names `build (spiceflare)`, `build (spiceflare-codegen)`, and `melange-check` are based on how GitHub Actions names matrix jobs. These should be verified after the first CI run by checking:

```bash
gh api /repos/anentropic/ocaml-spiceflare/commits/$(git rev-parse HEAD)/check-runs \
  --jq '.check_runs[].name'
```

If the names differ (e.g., GitHub prefixes with workflow name like `CI / build (spiceflare)`), update the protection command with the actual names.

### Task 2: Checkpoint - Verify CI runs and branch protection

**Status: Deferred pending Task 1 resolution.**

The checkpoint requires the user to:

1. Push the branch to GitHub (all CI workflow files from Plan 01 are already committed)
2. Wait for CI to run and verify all three checks pass:
   - `build (spiceflare)` -- builds the bindings package
   - `build (spiceflare-codegen)` -- builds the generator package
   - `melange-check` -- builds all melange.emit stanzas
3. Once the repo is public (or GitHub Pro is active), run the branch protection command above
4. Verify branch protection appears in the PR merge box

## Deviations from Plan

**1. [Rule 1 - Bug] Branch protection blocked by GitHub plan restriction**
- **Found during:** Task 1
- **Issue:** `gh api PUT /branches/main/protection` returned HTTP 403. The repository is private and the account is on the free GitHub tier. Branch protection for private repos requires GitHub Pro.
- **Fix:** Cannot auto-fix -- this is an account/visibility constraint. Documented exact commands to run once unblocked.
- **Files modified:** None
- **Commit:** N/A (no code changes)

## What Needs to Happen Next

To fully complete TEST-02 success criterion 3 ("CI failure on binding compile regression blocks merge"):

**Option A (recommended for open-source):** Make the repository public, then run the branch protection command above.

**Option B:** Upgrade to GitHub Pro, then run the branch protection command above.

After setting branch protection, verify by opening a test PR and confirming the three required checks appear in the merge box.

## Self-Check: PASSED

- No file changes were made (task was a remote API call only)
- Failure reason documented accurately (HTTP 403, private repo limitation)
- Commands to complete the task later are included and verified against ci.yml job names
