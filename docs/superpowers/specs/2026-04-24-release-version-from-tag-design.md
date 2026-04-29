# Release Version From Tag Design

## Goal

Make the Android release GitHub Actions workflow derive the app version name from a release tag such as `v1.2.3`, so the built APK reports that version inside the app.

## Current State

- `.github/workflows/android-release.yml` currently builds with `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
- Because the workflow does not pass `--build-name` or `--build-number`, the APK uses the version declared in `pubspec.yaml`
- The app reads its displayed version from `package_info_plus`, so the build-time version values determine what users see in the app
- `pubspec.yaml` currently declares `version: 1.0.10+10`

## Chosen Approach

For tag-triggered release builds:

- parse the tag `v1.2.3` into build name `1.2.3`
- pass that value to Flutter with `--build-name`
- derive a numeric `--build-number` from the tag itself so rebuilds of the same tag stay stable and Android version codes remain monotonic across releases

For manual `workflow_dispatch` runs:

- if `inputs.ref` explicitly names a supported release tag, derive version values using the same rules as an automatic tag-triggered release
- if `inputs.ref` explicitly looks like a tag reference but is invalid or unsupported, fail fast with a clear error instead of falling back
- otherwise, keep using the version already declared in `pubspec.yaml`

## Why This Approach

- It keeps the release tag format simple and conventional
- It updates the app-visible version for real tagged releases without requiring a `pubspec.yaml` edit for every release
- It keeps manual rebuilds of the same release tag reproducible while still avoiding version guesses for ordinary branch-based manual runs
- It accepts that release versioning is applied at CI build time rather than by mutating tracked source files

## Workflow Behavior Changes

Update `.github/workflows/android-release.yml` so the build step becomes conditional on the trigger type.

### Tagged release behavior

Supported release tags must match the exact canonical format `vMAJOR.MINOR.PATCH`, for example `v1.2.3`.

Each numeric component must use canonical decimal formatting with no leading zeros, except that the single digit `0` is allowed. For example:

- valid: `v1.2.3`, `v0.9.0`
- invalid: `v01.2.3`, `v1.02.3`, `v1.2.003`

Supported numeric bounds are:

- `0 <= MAJOR <= 2099`
- `0 <= MINOR <= 999`
- `0 <= PATCH <= 999`

Additionally, the all-zero version `v0.0.0` is not supported. The derived `BUILD_NUMBER` must be at least `1`.

These bounds keep the encoded Android `versionCode` within the Google Play `2100000000` ceiling and prevent collisions.

When the workflow runs from a supported tag:

1. Read `github.ref_name`
2. Strip the leading `v`
3. Use the remaining string as `BUILD_NAME`
4. Parse `MAJOR`, `MINOR`, and `PATCH` as integers
5. Compute `BUILD_NUMBER` from those components with a stable fixed-width encoding: `MAJOR * 1000000 + MINOR * 1000 + PATCH`
5. Run:

```bash
flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false --build-name "$BUILD_NAME" --build-number "$BUILD_NUMBER"
```

Example:

- tag: `v1.2.3`
- build name: `1.2.3`
- build number: `1002003`
- app version name shown in normal UI: `1.2.3`
- full `PackageInfo` tuple available to diagnostics/logging: `1.2.3+1002003`

If the tag does not match the supported `vMAJOR.MINOR.PATCH` format, or if any numeric part exceeds the supported bounds, the workflow must fail fast before the build step with a clear error message instead of silently producing an APK.

Within those bounds, version codes are stable, monotonic, and collision-free.

### Manual dispatch behavior

When the workflow runs via `workflow_dispatch`:

- accept either `v1.2.3` or `refs/tags/v1.2.3` as the manual `inputs.ref` form for a release-tag rebuild
- normalize `refs/tags/v1.2.3` to `v1.2.3` before validation
- if the normalized manual `inputs.ref` is a supported release tag such as `v1.2.3`, derive `BUILD_NAME` and `BUILD_NUMBER` using the same validation and encoding rules as a tag-triggered release build
- if `inputs.ref` is empty, keep using the existing build command without `--build-name` and `--build-number`
- if `inputs.ref` starts with `v` or `refs/tags/` but fails canonical release-tag validation after normalization, fail fast with a clear error instead of falling back to `pubspec.yaml`
- if `inputs.ref` is any other value, including branch refs like `refs/heads/main`, branch names, or commit SHAs, keep using the existing build command without `--build-name` and `--build-number`
- this preserves the `pubspec.yaml` version for ordinary manual validation builds while allowing reproducible manual rebuilds of release tags

## Release Notes Handling

This change does not automate release notes or GitHub Release publication.

The intended release flow is:

1. Merge code into `main`
2. Create and push a release tag such as `v1.0.11`
3. Let GitHub Actions build the APK with the tag-derived version
4. Write or edit the release notes manually on the GitHub Release page

## Scope

Modify only:

- `.github/workflows/android-release.yml`

No changes are needed in:

- `pubspec.yaml`
- Flutter app code under `lib/`
- `ci.yml`

This spec supersedes the Android release build command details in:

- `docs/superpowers/specs/2026-04-24-github-actions-design.md`
- `docs/superpowers/plans/2026-04-24-github-actions.md`

## Non-Goals

- No support for parsing tags like `v1.2.3+45`
- No automatic update of `pubspec.yaml`
- No GitHub Release publishing or APK attachment changes
- No version inference for manual builds from arbitrary branch names or non-release refs

## Reproducibility Note

This design intentionally applies the release version override only inside GitHub Actions for tagged builds and manual rebuilds that explicitly target a valid release tag.

That means:

- building locally from the same git tag with the plain repository command will still use the `pubspec.yaml` version
- reproducing the exact release APK version locally requires passing the same `--build-name` and `--build-number` overrides manually

This trade-off is intentional because it keeps source version bumps out of routine release tagging while still making the distributed APK report the tagged version.

## Validation

After implementation, verify by:

- checking the workflow YAML for correct conditional logic between tag-triggered runs, manual runs that target valid release tags, and manual runs that target ordinary refs
- checking the workflow YAML for explicit validation of supported tag format and fail-fast handling for invalid tags
- running `flutter analyze`
- running `flutter test`
- if feasible, using a local equivalent build command to confirm the tag-driven command shape is valid
- after push, manually confirming in GitHub that a tagged release run uses the derived build name and stable derived build number, that manual dispatch against the same release tag uses the same derived values, and that manual dispatch against an ordinary ref still uses the `pubspec.yaml` version
