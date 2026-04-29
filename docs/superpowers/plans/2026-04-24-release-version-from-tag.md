# Release Version From Tag Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `android-release.yml` so release-tag builds derive app version values from canonical `vMAJOR.MINOR.PATCH` tags while preserving `pubspec.yaml` versioning for ordinary manual builds.

**Architecture:** Keep all versioning logic inside the existing GitHub Actions workflow. Add a small shell step that normalizes and validates the release ref, conditionally exports derived `BUILD_NAME` and `BUILD_NUMBER`, then choose the correct Flutter build command based on whether tag-derived versioning is active.

**Tech Stack:** GitHub Actions YAML, shell scripting, Flutter build CLI

---

## File Map

### Modified files

- `.github/workflows/android-release.yml`
  - Add release-ref normalization and validation logic.
  - Add conditional build commands for tag-derived versus plain `pubspec.yaml` versioning.

### Reference files

- `docs/superpowers/specs/2026-04-24-release-version-from-tag-design.md`
  - Approved tag format, bounds, manual-dispatch rules, and validation expectations.

## Task 1: Add release-tag normalization and validation

**Files:**
- Modify: `.github/workflows/android-release.yml`

- [ ] **Step 1: Add a workflow step that determines versioning mode**

Update `.github/workflows/android-release.yml` to add a shell step before the APK build that:

- reads `github.ref_name` for automatic tag-triggered runs
- reads and normalizes `inputs.ref` for manual `workflow_dispatch` runs
- distinguishes among:
  - automatic tag-triggered runs
  - manual runs targeting valid release tags
  - manual runs with empty refs
  - manual runs targeting branch refs, branch names, or commit SHAs
  - invalid tag-like refs that must fail fast
- exports a boolean-style flag indicating whether tag-derived versioning is active

- [ ] **Step 2: Implement canonical release-tag validation**

The validation step must enforce all approved rules:

- accepted canonical tag form: `vMAJOR.MINOR.PATCH`
- accepted manual tag-ref forms: `v1.2.3` and `refs/tags/v1.2.3`
- no leading zeros except the single digit `0`
- bounds:
  - `0 <= MAJOR <= 2099`
  - `0 <= MINOR <= 999`
  - `0 <= PATCH <= 999`
- reject `v0.0.0`
- fail fast when a manual `ref` starts with `v` or `refs/tags/` but is invalid

- [ ] **Step 3: Export derived version values for valid release tags**

When a valid release tag is active, export:

- `BUILD_NAME=MAJOR.MINOR.PATCH`
- `BUILD_NUMBER=MAJOR * 1000000 + MINOR * 1000 + PATCH`

Use `$GITHUB_ENV` so later steps can consume the values.

## Task 2: Make the APK build command conditional

**Files:**
- Modify: `.github/workflows/android-release.yml`

- [ ] **Step 1: Replace the single build step with conditional build logic**

Update the workflow so that:

- when tag-derived versioning is active, it runs:

```bash
flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
```

- otherwise, it keeps the existing command:

```bash
flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false
```

- [ ] **Step 2: Keep the rest of the workflow unchanged**

Preserve:

- `workflow_dispatch` and `push.tags` triggers
- checkout behavior using `inputs.ref || github.ref`
- Flutter setup, Java setup, and artifact upload
- artifact name and retention
- explicit `permissions: contents: read`

## Task 3: Verify workflow logic and project health

**Files:**
- Modify only if verification exposes defects

- [ ] **Step 1: Review the final YAML for all execution paths**

Manually inspect `.github/workflows/android-release.yml` to confirm the workflow now handles:

- tag push with valid canonical tag
- manual dispatch with `v1.2.3`
- manual dispatch with `refs/tags/v1.2.3`
- manual dispatch with empty `ref`
- manual dispatch with branch-like refs
- manual dispatch with invalid tag-like refs

Negative cases to check explicitly in the shell validation logic:

- `v01.2.3`
- `v1.02.3`
- `v1.2.003`
- `v0.0.0`
- `v2100.0.0`
- `v1.1000.0`
- `v1.0.1000`

Confirm these invalid tag-like refs fail before the build step with a clear error message.

- [ ] **Step 2: Run repository verification commands**

Run: `flutter analyze`
Expected: PASS.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: If feasible, validate the tag-derived command shape locally**

Run a local equivalent command such as:

```bash
flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false --build-name 1.2.3 --build-number 1002003
```

Expected: the command is accepted by Flutter. If the local environment cannot complete the full build, record that limitation explicitly.

- [ ] **Step 4: Review the scoped diff**

Run: `git diff -- .github/workflows/android-release.yml`
Expected: only the approved workflow changes are included.

- [ ] **Step 5: Note GitHub-side follow-up verification**

Record that full behavior still needs GitHub-side confirmation after push:

- push a valid release tag and inspect derived versioning
- manually dispatch against the same release tag and confirm matching derived values
- manually dispatch against a normal ref and confirm fallback to `pubspec.yaml`
- manually dispatch against an invalid tag-like ref and confirm fail-fast behavior

## Task 4: Prepare handoff or commit

**Files:**
- Modify only if verification exposes defects

- [ ] **Step 1: Summarize the final behavior**

Record which refs now activate tag-derived versioning, which refs fall back to `pubspec.yaml`, and which refs fail fast.

- [ ] **Step 2: Commit if requested**

```bash
git add .github/workflows/android-release.yml
git commit -m "Derive release version from tags"
```
