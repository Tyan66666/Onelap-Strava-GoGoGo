# Release Publish Checkout Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `Android Release` workflow so the tag-triggered `publish` job can create or update GitHub Releases successfully.

**Architecture:** Keep the existing build and publish workflow intact, but restore the git repository context expected by `gh release` by adding checkout to the `publish` job. Verify by rerunning the failed `v1.0.12` release workflow after the fix reaches the target branch.

**Tech Stack:** GitHub Actions YAML, GitHub CLI, git worktrees

---

### Task 1: Update publish job repository context

**Files:**
- Modify: `.github/workflows/android-release.yml`

- [ ] **Step 1: Work from an isolated worktree**

Run: `git worktree add ".worktrees/release-publish-fix" -b "fix/release-publish-checkout" origin/main`
Expected: a clean isolated worktree based on `origin/main` is available for the workflow fix.

- [ ] **Step 2: Confirm the failing behavior context**

Run: `gh run view 24898847939 --job 72912598145 --log`
Expected: log shows `failed to run git: fatal: not a git repository` in the `Create or update GitHub release` step.

- [ ] **Step 3: Add the minimal workflow fix**

Insert `actions/checkout@v4` near the start of the `publish` job, before `actions/download-artifact@v4`.

- [ ] **Step 4: Inspect the resulting workflow diff**

Run: `git diff -- .github/workflows/android-release.yml`
Expected: only the `publish` job gains a checkout step.

- [ ] **Step 5: Commit the workflow fix**

Run: `git add .github/workflows/android-release.yml && git commit -m "Fix release publish checkout context"`
Expected: one commit containing only the workflow change.

### Task 2: Put the fix on a branch that can be exercised

**Files:**
- Modify: branch state only

- [ ] **Step 1: Push the fix branch**

Run: `git push -u origin fix/release-publish-checkout`
Expected: remote branch created and tracking set.

- [ ] **Step 2: Decide verification path**

Merge or otherwise land the fix on `main` before verification.
Expected: the target branch used by release tags contains the corrected workflow file.

### Task 3: Verify the real release publication behavior

**Files:**
- Verify: GitHub Actions run and GitHub Release state

- [ ] **Step 1: Trigger verification after the fix is on the target branch**

Re-run or re-trigger the `v1.0.12` release workflow only after the fixed workflow is on `main`.

- [ ] **Step 2: Watch the run to completion**

Run: `gh run watch <run-id> --interval 10`
Expected: both `build` and `publish` complete successfully.

- [ ] **Step 3: Verify the GitHub Release result**

Run: `gh release view v1.0.12 --json url,name,assets,body`
Expected: release `v1.0.12` exists and includes `app-release.apk`.

- [ ] **Step 4: Record any residual follow-up**

If verification succeeds, note that the workflow remains subject to GitHub's Node 20 deprecation warnings but the release flow is fixed.
