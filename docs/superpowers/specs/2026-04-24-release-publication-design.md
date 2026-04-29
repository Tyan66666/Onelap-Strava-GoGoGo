# Release Publication Design

## Goal

1. Create the missing `v1.0.11` GitHub Release with the APK built by the existing `Android Release` workflow and a user-provided description.
2. Extend the release workflow so future release tags automatically create or update a GitHub Release and attach the generated APK.

## Current State

- Tag `v1.0.11` exists and successfully triggered `Android Release`
- Workflow run `24894750837` completed successfully and uploaded artifact `android-release-apk`
- The workflow currently only uploads an Actions artifact and does not create a GitHub Release
- `gh release list` shows no `v1.0.11` release yet

## Chosen Approach

Handle the current release manually, then automate future ones in the workflow.

### Current `v1.0.11` release

- Create `v1.0.11` as a GitHub Release manually via `gh release create`
- Download the APK from workflow run `24894750837`
- Attach that APK to the release
- Use the user-approved release body exactly as provided

Release body for `v1.0.11`:

```md
## 更新内容
- 修复 OneLap token 同步流程
- 更新应用版本到 1.0.11
```

### Future tagged releases

Update `.github/workflows/android-release.yml` so that after a successful tagged build it:

- creates the GitHub Release if it does not already exist
- or updates/uploads assets if the Release already exists
- uploads the generated APK as a release asset
- uses a fixed placeholder release description template for now

Placeholder release body for future automated releases:

```md
## 更新内容
- 请补充本次版本说明
```

## Why This Approach

- It fixes the immediate missing `v1.0.11` release without waiting on new automation
- It keeps current and future work separated, reducing risk while closing the present gap
- It gives future tags a complete release flow even before richer release-note automation exists

## Manual Release Handling

For `v1.0.11` only:

1. Download the APK artifact from workflow run `24894750837`
2. Create GitHub Release `v1.0.11`
3. Set the title to `v1.0.11`
4. Use the approved body text above
5. Upload the APK as a release asset named `app-release.apk`

This step is intentionally one-off and should not require rerunning the tag workflow.

## Workflow Behavior Changes

Modify `.github/workflows/android-release.yml` for future tagged runs only.

The workflow should be split into:

- a build job that always handles checkout, version resolution, Flutter setup, APK build, and artifact upload with read-only contents access
- a separate tag-only publish job that depends on the build job, downloads the built APK artifact, and performs GitHub Release publication with `contents: write`

### Tagged release behavior

When triggered by a valid release tag push:

1. Build the APK as the workflow already does
2. Create a temporary release-notes file containing the placeholder body
3. Create the release if it does not exist yet, using the tag itself as the release title, for example `v1.0.12`
4. Upload the APK file to that release as `app-release.apk`
5. If the release already exists, preserve its existing title and body and only replace the APK asset if needed

Implementation should use `gh release view`, `gh release create`, and `gh release upload --clobber`.

The release publication steps must export `GH_TOKEN=${{ github.token }}` so the GitHub CLI can authenticate with the workflow token.

### Manual dispatch behavior

Manual `workflow_dispatch` runs should keep their current role as validation builds.

- Do not auto-create GitHub Releases from manual runs
- Do not upload release assets from manual runs
- Continue uploading the Actions artifact only

## Permissions Changes

The workflow currently uses `permissions: contents: read`.

To keep validation builds narrow while allowing release publication on tag runs, scope write access only to a separate tag-only publish job.

- the build job should remain at `contents: read`
- the publish job should use `contents: write`

No broader permissions are needed.

## Scope

Modify:

- `.github/workflows/android-release.yml`

Perform one operational release action for:

- existing tag `v1.0.11`

No changes are needed in:

- `pubspec.yaml`
- Flutter app code under `lib/`
- `.github/workflows/ci.yml`

## Non-Goals

- No automatic generation of release notes from commits, tags, or changelog files
- No retroactive automation for older releases before `v1.0.11`
- No Play Store publishing or other external distribution
- No workflow changes for manual non-tag builds beyond preserving current behavior

## Validation

After implementation, verify by:

- confirming `v1.0.11` exists as a GitHub Release with the approved description and APK asset attached
- confirming the updated workflow YAML explicitly contains tag-only release publication logic, placeholder notes creation, `gh release create`, and `gh release upload --clobber`
- confirming manual `workflow_dispatch` still does not create a release
- running `flutter analyze`
- running `flutter test`
