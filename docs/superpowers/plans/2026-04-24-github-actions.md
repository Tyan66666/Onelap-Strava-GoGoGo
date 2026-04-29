# GitHub Actions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions workflows for routine Flutter CI and Android release APK artifact builds.

**Architecture:** Add two focused workflow files under `.github/workflows/`. Keep routine validation in `ci.yml` for pull requests and direct pushes to `main`, and isolate heavier Android APK generation in `android-release.yml` for tags and manual runs.

**Tech Stack:** GitHub Actions, Flutter 3.41.5, Dart, Android Gradle, YAML

---

## File Map

### Created files

- `.github/workflows/ci.yml`
  - Runs formatting checks, static analysis, and tests on Ubuntu for `pull_request` and `push` to `main`.
- `.github/workflows/android-release.yml`
  - Builds the Android release APK on Ubuntu for `workflow_dispatch` and `v*` tags, then uploads the APK artifact.

### Existing files to reference

- `docs/superpowers/specs/2026-04-24-github-actions-design.md`
  - Approved design decisions for workflow scope, triggers, action choices, and verification.
- `android/app/build.gradle.kts`
  - Confirms Java 17 is required and that release builds currently use the debug signing config.
- `README.md`
  - Source of truth for the Android release build command.

## Task 1: Add routine Flutter CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the CI workflow YAML**

Create `.github/workflows/ci.yml` with:

- triggers for `pull_request` and `push` to `main`
- `ubuntu-latest` runner
- `actions/checkout@v4`
- `subosito/flutter-action@v2` configured with `flutter-version: 3.41.5`, `channel: stable`, and built-in pub caching enabled
- steps for `flutter pub get`, `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test`

Use this exact shape as the starting point:

```yaml
name: CI

on:
  pull_request:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.41.5
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Check formatting
        run: dart format --output=none --set-exit-if-changed lib test

      - name: Analyze
        run: flutter analyze

      - name: Run tests
        run: flutter test
```

- [ ] **Step 2: Review the CI workflow against the approved spec**

Check:

- trigger scope is only `pull_request` plus `push` to `main`
- no secrets or unnecessary permissions are added
- commands match the repository guidance exactly

## Task 2: Add Android release APK workflow

**Files:**
- Create: `.github/workflows/android-release.yml`

- [ ] **Step 1: Write the Android release workflow YAML**

Create `.github/workflows/android-release.yml` with:

- triggers for `workflow_dispatch` and `push` tags matching `v*`
- one optional manual input named `ref`
- checkout logic that uses the `ref` input when present, otherwise `github.ref`
- `ubuntu-latest` runner
- `actions/checkout@v4`
- `subosito/flutter-action@v2` configured with `flutter-version: 3.41.5`, `channel: stable`, and built-in pub caching enabled
- `actions/setup-java@v4` with `distribution: temurin` and `java-version: 17`
- steps for `flutter pub get` and `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
- `actions/upload-artifact@v4` uploading `build/app/outputs/flutter-apk/app-release.apk` as `android-release-apk` with `retention-days: 7`

Use this exact shape as the starting point:

```yaml
name: Android Release

on:
  workflow_dispatch:
    inputs:
      ref:
        description: Git ref to build
        required: false
        type: string
  push:
    tags:
      - "v*"

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.ref || github.ref }}

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.41.5
          channel: stable
          cache: true

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Install dependencies
        run: flutter pub get

      - name: Build release APK
        run: flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false

      - name: Upload APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: android-release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
          retention-days: 7
```

- [ ] **Step 2: Review the Android workflow against the approved spec**

Check:

- tag trigger pattern is `v*`
- manual dispatch input name is exactly `ref`
- Java 17 setup is explicit
- artifact path and name match the spec exactly

## Task 3: Verify workflow syntax and project checks

**Files:**
- Modify only if verification exposes workflow defects

- [ ] **Step 1: Format and inspect changed YAML files**

Review `.github/workflows/ci.yml` and `.github/workflows/android-release.yml` for indentation, quoting, and trigger structure.

- [ ] **Step 2: Run the repository quality checks locally**

Run: `dart format --output=none --set-exit-if-changed lib test`
Expected: PASS.

Run: `flutter analyze`
Expected: PASS.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Run the Android release build command locally if feasible**

Run: `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
Expected: PASS and produce `build/app/outputs/flutter-apk/app-release.apk`.

If the local environment cannot complete a release build, record that limitation explicitly and continue with the remaining verification steps rather than blocking the workflow implementation.

- [ ] **Step 4: Review the scoped diff**

Run: `git diff -- .github/workflows/ci.yml .github/workflows/android-release.yml`
Expected: only the approved workflow files are included in the implementation diff.

- [ ] **Step 5: Verify GitHub accepts the workflows**

After the workflow files are pushed to a branch, open a test pull request and confirm in GitHub that:

- the `ci.yml` workflow is discovered and starts on the expected event
- the workflow YAML is accepted without syntax errors
- the `android-release.yml` workflow appears in the Actions tab for manual dispatch
- a manual dispatch of `android-release.yml` can be started successfully, ideally once with the default run ref and once with an explicit `ref` input when practical

Expected: GitHub recognizes both workflows, starts the CI job for the pull request event, and accepts at least one manual `android-release.yml` run.

## Task 4: Prepare handoff or commit

**Files:**
- Modify only if verification exposes defects

- [ ] **Step 1: Summarize verification evidence**

Record which local checks passed, whether the APK build succeeded, and whether GitHub-side workflow discovery/startup was confirmed.

- [ ] **Step 2: Commit if requested**

```bash
git add .github/workflows/ci.yml .github/workflows/android-release.yml
git commit -m "Add GitHub Actions CI workflows"
```
