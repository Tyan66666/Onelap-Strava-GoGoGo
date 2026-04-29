# Release Publication Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the missing `v1.0.11` GitHub Release with its APK and description, then extend the release workflow so future tag builds automatically publish or update GitHub Releases.

**Architecture:** Handle the current `v1.0.11` release as a one-off operational action using the already-built artifact. Then evolve `.github/workflows/android-release.yml` into two jobs: a read-only build job that produces the APK artifact, and a tag-only publish job with `contents: write` that creates or updates the GitHub Release and uploads `app-release.apk`.

**Tech Stack:** GitHub CLI (`gh`), GitHub Actions YAML, Flutter build workflow

---

## File Map

### Modified files

- `.github/workflows/android-release.yml`
  - Split release flow into a build job and a tag-only publish job.
  - Keep manual validation behavior unchanged.
  - Add release publication steps using `gh`.

### Operational targets

- existing workflow run `24894750837`
  - Source of the already-built `v1.0.11` APK artifact.
- GitHub Release `v1.0.11`
  - One-off release to create and populate now.

### Reference files

- `docs/superpowers/specs/2026-04-24-release-publication-design.md`
  - Approved design decisions for one-off release creation and future automation.

## Task 1: Create the missing `v1.0.11` release

**Files:**
- No repository file changes required for this task

- [ ] **Step 1: Download the existing APK artifact from run `24894750837`**

Use GitHub CLI to download the `android-release-apk` artifact from run `24894750837` into a temporary local directory.

- [ ] **Step 2: Rename or confirm the asset as `app-release.apk`**

Prepare the uploaded asset filename as exactly `app-release.apk`.

- [ ] **Step 3: Create GitHub Release `v1.0.11` with the approved body**

Use `gh release create` to create release `v1.0.11` with:

- title: `v1.0.11`
- body:

```md
## 更新内容
- 修复 OneLap token 同步流程
- 更新应用版本到 1.0.11
```

- [ ] **Step 4: Upload the APK asset to `v1.0.11`**

Attach `app-release.apk` to the new release.

- [ ] **Step 5: Verify the release exists and contains the asset**

Run: `gh release view v1.0.11`
Expected: release exists with the approved body and `app-release.apk` attached.

## Task 2: Automate release publication for future tags

**Files:**
- Modify: `.github/workflows/android-release.yml`

- [ ] **Step 1: Split the workflow into build and publish jobs**

Refactor the workflow so that:

- `build` job continues to handle checkout, version resolution, Flutter setup, Java setup, dependency install, APK build, and artifact upload
- `build` job keeps `permissions: contents: read`
- new `publish` job depends on `build`
- `publish` job runs only for tag-triggered builds, not manual dispatch builds
- `publish` job uses `permissions: contents: write`

- [ ] **Step 2: Keep existing build behavior unchanged**

Preserve in the `build` job:

- release tag version derivation logic
- manual-dispatch fallback behavior
- artifact upload of the built APK

- [ ] **Step 3: Add release publication steps to the publish job**

Implement publish-job logic that:

- exports `GH_TOKEN=${{ github.token }}`
- downloads the built artifact named `android-release-apk` from the current workflow run
- expects the downloaded APK file at `app-release.apk` after extraction/rename before upload
- prepares placeholder notes file with:

```md
## 更新内容
- 请补充本次版本说明
```

- passes that notes file to `gh release create` as the release body when creating a new release

- uses `gh release view` to check whether the tag release already exists
- uses `gh release create` when absent, with title equal to the tag name
- uses `gh release upload --clobber` to upload or replace `app-release.apk`
- preserves existing release title/body when the release already exists

- [ ] **Step 4: Keep manual runs artifact-only**

Verify the workflow does not create or update GitHub Releases when triggered by `workflow_dispatch`.

Record concrete acceptance evidence to check after implementation:

- the `publish` job is gated so it does not run for `workflow_dispatch`
- manual runs continue to upload the `android-release-apk` Actions artifact only
- no new GitHub Release is created or edited by a manual run

## Task 3: Verify workflow and repository health

**Files:**
- Modify only if verification exposes defects

- [ ] **Step 1: Review final workflow YAML structure**

Confirm the workflow clearly contains:

- read-only `build` job
- tag-only `publish` job with `contents: write`
- placeholder notes creation
- `gh release create`
- `gh release upload --clobber`

- [ ] **Step 2: Run repository verification commands**

Run: `flutter analyze`
Expected: PASS.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Review the scoped diff**

Run: `git diff -- .github/workflows/android-release.yml`
Expected: only the approved workflow automation changes are included.

- [ ] **Step 4: Verify the one-off release outcome**

Confirm via GitHub CLI that `v1.0.11` now exists with:

- the approved body text
- asset `app-release.apk`

## Task 4: Prepare handoff or commit

**Files:**
- Modify only if verification exposes defects

- [ ] **Step 1: Summarize final behavior**

Record:

- that `v1.0.11` was created manually with the requested description and asset
- that future tag pushes will auto-publish releases
- that manual `workflow_dispatch` remains artifact-only

- [ ] **Step 2: Commit if requested**

```bash
git add .github/workflows/android-release.yml
git commit -m "Automate GitHub release publication"
```
