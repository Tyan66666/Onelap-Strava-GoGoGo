# GitHub Actions Design

## Goal

Add GitHub Actions automation for this Flutter project in two layers:

- fast pull-request and `main` branch CI for code quality
- separate Android release APK builds for tags or manual runs

## Current State

- The repository does not currently contain any files under `.github/workflows/`
- The project already documents a recommended verification flow in `AGENTS.md`: `dart format lib test`, `flutter analyze`, and `flutter test`
- `README.md` documents the release APK build command as `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
- The repository already contains meaningful widget and service tests under `test/`
- Recent commits include Android and iOS project changes, so automation should catch Dart-level regressions on every PR and validate Android release builds through a separate workflow

## Chosen Approach

Create two separate workflows:

1. `ci.yml` for routine validation on `pull_request` and `push` to `main`
2. `android-release.yml` for release APK generation on version tags and manual dispatch

## Why This Approach

- It keeps the common PR feedback loop fast by limiting routine checks to formatting, static analysis, and tests
- It verifies the release build command without forcing every PR to pay the full release-build cost
- It matches the repository's current needs better than a single all-in-one workflow or a deployment-oriented pipeline

## Workflow 1: CI

### Purpose

Protect the main branch and pull requests from common regressions in Dart and Flutter code.

### Trigger

- `pull_request`
- `push` to `main`

This workflow does not run on every branch push. Feature branches are expected to be validated through pull requests, while direct pushes to `main` still receive CI coverage.

### Steps

1. Check out the repository
2. Install Flutter with `subosito/flutter-action@v2`, pinned to Flutter SDK `3.41.5` on the stable channel
3. Enable that action's built-in pub dependency cache rather than adding a custom cache block
4. Run `flutter pub get`
5. Run `dart format --output=none --set-exit-if-changed lib test`
6. Run `flutter analyze`
7. Run `flutter test`

### Notes

- This workflow should fail on formatting drift rather than rewriting files
- No secrets are needed for this workflow
- The workflow should stay Linux-only unless a real platform-specific validation need appears

## Workflow 2: Android Release

### Purpose

Produce a release APK artifact from the exact command documented in the repository.

### Trigger

- `workflow_dispatch`
- `push` tags matching `v*`

Manual dispatch should allow selecting the target ref so release builds can be tested before cutting a version tag. Use one optional string input named `ref`; when provided, checkout should use that ref, and when omitted, checkout should use the GitHub Actions run ref from `github.ref` for that manual run.

### Steps

1. Check out the repository
2. Install Flutter with `subosito/flutter-action@v2`, pinned to Flutter SDK `3.41.5` on the stable channel
3. Install JDK 17 with `actions/setup-java@v4` using the `temurin` distribution to match `android/app/build.gradle.kts`
4. Enable the Flutter action's built-in pub dependency cache rather than adding a custom cache block
5. Run `flutter pub get`
6. Run `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
7. Upload `build/app/outputs/flutter-apk/app-release.apk` with `actions/upload-artifact@v4` as a workflow artifact named `android-release-apk` with `retention-days: 7`

### Notes

- This workflow is intentionally artifact-only for now; it does not create GitHub Releases automatically
- This workflow assumes the repository can produce a CI artifact without private signing secrets. The current Android config explicitly signs release builds with the debug signing config, so the workflow can build and upload a release APK artifact today without a keystore secret. If that setup changes later, secret-backed signing should be added in a separate follow-up
- Manual dispatch is useful for testing the pipeline before the first version tag release

## Non-Goals

- No iOS or macOS build workflow in this change
- No automatic deployment to app stores or external services
- No scheduled workflows for OneLap/Strava sync, since this is a client app rather than a backend job
- No release-note generation or GitHub Release publishing yet

## Files To Add

- `.github/workflows/ci.yml`
- `.github/workflows/android-release.yml`

## Testing And Verification

After implementation, verify by:

- reviewing workflow YAML for trigger and path correctness
- running the local recommended checks where practical: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`
- if feasible, validating the release build command locally: `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
- opening a test pull request or branch push after workflow creation to confirm GitHub accepts the workflow syntax and the jobs start correctly

## Follow-Up Options

Potential later additions, but not part of this design:

- GitHub Release creation on tags
- Android debug build validation in CI if release builds prove too slow to run frequently
- dependency update automation such as Dependabot
- platform-specific build jobs if the repository starts validating iOS or desktop targets in CI
