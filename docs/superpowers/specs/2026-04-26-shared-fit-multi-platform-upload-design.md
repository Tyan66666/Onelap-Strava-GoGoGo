# Design: Shared FIT Multi-Platform Upload

**Date:** 2026-04-26  
**Status:** Draft  
**Scope:** Make Android system-share FIT uploads follow the same platform-selection settings as normal sync, while extracting a reusable multi-platform upload layer for future expansion.

## Goal

When the user shares a FIT file into WanSync from the system share sheet, the app should upload to the same enabled target platforms configured in Settings.

Expected behavior:

- if only Strava is enabled, upload only to Strava,
- if only Xingzhe is enabled, upload only to Xingzhe,
- if both are enabled, upload to both platforms,
- if no upload platform is enabled, prompt the user to configure settings instead of attempting upload.

This behavior should no longer be hard-coded to Strava.

The implementation should also improve reuse: the code that selects platforms, validates platform configuration, dispatches per-platform uploads, and aggregates platform results should live in a dedicated reusable layer instead of staying embedded inside the share-specific service.

## Current State

The current share upload flow is separate from the OneLap sync flow:

- `lib/services/shared_fit_upload_service.dart` validates the shared file, loads settings, optionally rewrites FIT coordinates, and uploads,
- `lib/screens/share_confirm_screen.dart` presents a confirmation UI and displays share upload outcomes,
- `lib/services/sync_engine.dart` already supports both Strava and Xingzhe for OneLap sync runs.

The current bug exists because `SharedFitUploadService` still has single-platform logic:

- it only checks required Strava configuration,
- it only instantiates and calls `StravaClient`,
- its UI text is written as if every share upload goes only to Strava.

As a result, the Settings toggles `UPLOAD_TO_STRAVA` and `UPLOAD_TO_XINGZHE` do not control the system-share upload path.

## Chosen Approach

Introduce a new reusable multi-platform FIT upload coordinator layer and make the shared FIT flow call that layer after file validation and optional coordinate rewriting.

This design keeps the current share entrypoint intact while extracting the platform-selection and per-platform upload dispatch logic into focused reusable types.

For this task, `SyncEngine` will not be fully refactored to use the new coordinator. The extracted layer will instead establish the reusable boundary now, so future work can migrate more upload paths without forcing a broad refactor in this bug-fix change.

## Why This Approach

- It fixes the user-visible bug at the actual branching point: the share upload flow.
- It improves reuse where it matters most for future platform expansion: target-platform resolution and per-platform upload dispatch.
- It avoids forcing the local-file share flow into `SyncEngine`, which currently also owns OneLap listing, download, dedupe, state persistence, and sync statistics.
- It creates a clean extension point for additional platforms without requiring the system-share path to gain more hard-coded branches.

## Alternatives Considered

### 1. Patch `SharedFitUploadService` in place with Strava/Xingzhe branches

Rejected because it would fix the immediate bug but keep the share path tightly coupled to explicit platform conditionals, making the next platform addition more repetitive.

### 2. Reuse `SyncEngine` directly for shared local FIT uploads

Rejected because `SyncEngine` currently owns much more than uploading. It is built around OneLap activity discovery, dedupe keys, upload history, and sync summary accounting. Reusing it directly for a single shared local file would blur responsibilities and increase change risk.

### 3. Fully refactor all upload logic in one change

Rejected for this task because the bug is narrow and user-visible now. A full convergence of `SyncEngine` and the share path would broaden the diff and testing surface significantly.

## Execution Design

### Layer Boundaries

Split the share upload path into three responsibility layers.

#### 1. `SharedFitUploadService`

Keep this service focused on share-entry concerns only:

- verify the shared file looks like a FIT file,
- verify the local file is readable,
- load settings,
- optionally run GCJ coordinate rewriting,
- hand the final upload `File` plus settings to the new multi-platform coordinator,
- clean up any rewritten temporary file.

This service should stop making platform decisions itself.

#### 2. Multi-platform upload coordinator

Add a new service responsible for:

- parsing upload target toggles from settings,
- determining the enabled target platforms for the current upload,
- validating that each enabled platform has the configuration it requires,
- calling each platform uploader in sequence,
- returning a structured per-platform result summary.

The coordinator should not know anything about Android share intake, Flutter widgets, OneLap API fetches, or dedupe state.

#### 3. Platform uploaders

Add focused per-platform uploaders such as:

- `StravaFitUploader`
- `XingzheFitUploader`

Each uploader should only encapsulate its platform-specific upload mechanics:

- create or receive the underlying API client,
- upload the FIT file,
- poll for completion if the platform uses async processing,
- normalize platform-specific success, duplicate, and error shapes into a small shared result contract.

Platform uploaders should not inspect Settings toggles or decide whether they are enabled for a run.

### Settings Interpretation

The coordinator should treat these settings as the source of truth:

- `SettingsService.keyUploadToStrava`
- `SettingsService.keyUploadToXingzhe`

Boolean parsing should remain tolerant of existing storage conventions by treating a trimmed lowercase string value of `true` as enabled.

Target selection rules:

- only Strava enabled: upload only to Strava,
- only Xingzhe enabled: upload only to Xingzhe,
- both enabled: upload to both,
- neither enabled: return `missingConfiguration` at the share-service level.

### Platform Configuration Validation

The coordinator should validate configuration only for the enabled target platforms.

Required configuration by platform:

- Strava: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`, `STRAVA_REFRESH_TOKEN`
- Xingzhe: `XINGZHE_USERNAME`, `XINGZHE_PASSWORD`

If a platform is enabled but missing required configuration, the upload should not start. The coordinator should report that configuration is incomplete.

`XINGZHE_SESSION_ID` should be treated as reusable cached authentication state, not as mandatory setup. If it is present, the Xingzhe uploader may reuse it to avoid an extra login. If it is absent or stale, the uploader should be allowed to authenticate with username and password and continue.

For this task, missing configuration should be treated as a blocking setup issue for the requested share upload rather than a partial best-effort upload.

Examples:

- Strava enabled but credentials missing: `missingConfiguration`
- Xingzhe enabled but credentials missing: `missingConfiguration`
- both enabled and Xingzhe config missing: `missingConfiguration`

This keeps setup semantics simple and predictable for the user: the enabled target set must be fully configured before the share upload begins.

### Result Model

Keep the existing top-level `SharedFitUploadStatus` values for the share screen:

- `missingConfiguration`
- `invalidFile`
- `success`
- `failure`

Under that outer status, introduce a structured internal result model from the coordinator that preserves per-platform outcomes.

Before upload begins, the coordinator should also expose a lightweight preflight result used by the share screen to describe the configured targets. A concrete API can be a new method such as `resolveUploadPlan(settings)` or a dedicated preflight call on `SharedFitUploadService` that returns:

- the enabled target platform list,
- whether any enabled platform is missing required configuration,
- a human-readable target label for the confirmation UI.

This preflight contract should be the single source of truth for upload-target wording before the user taps the upload button.

Each platform result should capture:

- target platform identifier,
- status such as `success`, `alreadyUploaded`, or `failure`,
- optional message,
- optional remote activity identifier when naturally available.

`alreadyUploaded` is included even though the share flow may initially treat it the same as success. The coordinator is intended to be reusable, and duplicate/idempotent outcomes are real platform behaviors already handled elsewhere in the app.

The share service should fold coordinator results into the existing top-level result using these rules:

- at least one `success` or `alreadyUploaded` platform result: top-level `success`,
- all attempted platforms failed: top-level `failure`,
- no enabled platforms or enabled platform config missing: top-level `missingConfiguration`.

When some platforms succeed and some fail, the share service should still return top-level `success`, but include a message that makes the partial outcome visible to the UI.

The coordinator must isolate failures per platform so it can continue attempting all enabled upload targets. Concretely, a Strava failure must be captured into the Strava platform result and must not prevent a subsequent Xingzhe upload attempt in the same run, and vice versa.

Example messages:

- `FIT 文件已经上传到 Strava。`
- `FIT 文件已经上传到行者。`
- `FIT 文件已经上传到 Strava 和行者。`
- `已上传到 Strava；行者上传失败：session expired`

The message-generation logic should be centralized so the UI does not need to understand every per-platform combination itself.

### Share Confirmation UI

`ShareConfirmScreen` should stop presenting fixed Strava-only copy.

The screen should derive target-platform wording from the preflight target metadata exposed by the share upload service rather than guessing from static copy.

Required behavior changes:

- initial confirmation button text should describe the enabled targets rather than always saying `上传到 Strava`,
- success text should mention the actual successful platform set,
- missing-configuration text should refer to the enabled upload targets rather than naming only Strava,
- partial-success results should be visible to the user instead of being flattened into a generic success sentence.

If no platform is enabled, the existing `去设置` recovery path remains correct.

### Interaction With GCJ Rewrite

The current coordinate rewrite behavior in `SharedFitUploadService` should remain intact:

- if GCJ correction is disabled, upload the original shared file,
- if GCJ correction is enabled, rewrite once and pass the rewritten file to the coordinator,
- if both platforms are enabled, both uploads should reuse the same rewritten file,
- if a rewritten temp file was created, delete it after upload attempts finish.

The coordinator should receive a ready-to-upload file and should not own rewrite concerns.

### Future Reuse With `SyncEngine`

This task should stop at extracting the reusable upload coordination boundary and using it from the share flow.

`SyncEngine` may continue to manage:

- OneLap activity listing and download,
- dedupe key and fingerprint handling,
- state persistence in `StateStore`,
- sync summary accounting and historical records,
- idempotent-success interpretation specific to sync history.

Future work can migrate selected upload-dispatch pieces from `SyncEngine` into the same reusable layer once that refactor is justified by another task.

## Testing Design

Follow TDD for the change.

### Coordinator Unit Tests

Add focused tests for the new coordinator covering:

- only Strava enabled calls only the Strava uploader,
- only Xingzhe enabled calls only the Xingzhe uploader,
- both enabled calls both uploaders,
- neither enabled returns no-targets / missing-configuration behavior,
- tolerant boolean parsing for settings values such as `true`, `TRUE`, and ` true `,
- an enabled platform with missing required config blocks upload,
- both enabled with one platform config missing blocks upload before any platform attempt starts,
- one platform success and one platform failure produces a partial-success aggregate,
- one platform failure still allows the second enabled platform to run,
- a duplicate/idempotent uploader outcome is normalized as `alreadyUploaded`,
- all attempted platforms failing produces an aggregate failure.

### Shared FIT Upload Service Tests

Update `test/services/shared_fit_upload_service_test.dart` so it reflects the new boundary and behavior:

- invalid extension still returns `invalidFile`,
- unreadable file still returns `invalidFile`,
- the service delegates to the coordinator instead of a Strava-only upload callback,
- GCJ rewrite happens before coordinator upload,
- rewritten temp files are deleted after the upload attempt,
- coordinator partial-success results map to top-level `success` with a user-visible message,
- missing enabled-platform configuration maps to `missingConfiguration`.

### Share Confirmation Screen Tests

Update `test/screens/share_confirm_screen_test.dart` to cover:

- confirmation button text for Strava-only, Xingzhe-only, and dual-platform uploads,
- confirmation button text driven by preflight target metadata before upload starts,
- success messaging for Strava-only, Xingzhe-only, dual-platform, and partial-success outcomes,
- missing-configuration messaging that does not hard-code Strava when the enabled targets differ.

### Verification Commands

After implementation, run the narrowest relevant checks first, then broader validation:

```bash
flutter test test/services/shared_fit_upload_service_test.dart
flutter test test/screens/share_confirm_screen_test.dart
flutter test
flutter analyze
```

If new coordinator tests live in a separate file, run that file explicitly before the full `flutter test` run.

## Files Expected To Change

| File | Change |
|---|---|
| `lib/services/shared_fit_upload_service.dart` | Remove Strava-only branching and delegate platform dispatch to the new coordinator |
| `lib/services/settings_service.dart` | Reuse existing upload-target keys as the coordinator source of truth; no key changes expected |
| `lib/services/strava_fit_uploader.dart` | New focused Strava uploader abstraction |
| `lib/services/xingzhe_fit_uploader.dart` | New focused Xingzhe uploader abstraction |
| `lib/services/fit_upload_coordinator.dart` | New reusable multi-platform upload coordination layer |
| `lib/screens/share_confirm_screen.dart` | Update confirmation, success, and missing-config copy to follow actual targets |
| `test/services/shared_fit_upload_service_test.dart` | Rewrite tests around coordinator delegation and platform-aware results |
| `test/services/fit_upload_coordinator_test.dart` | New regression coverage for target selection, config validation, and result aggregation |
| `test/screens/share_confirm_screen_test.dart` | Verify platform-aware share UI messaging |

## Non-Goals

- fully refactoring `SyncEngine` to use the coordinator in this task,
- changing OneLap sync dedupe or state persistence behavior,
- changing Android share-intake manifest or native event plumbing,
- adding batch multi-file share upload,
- changing iOS or desktop share behavior.

## Risks And Mitigations

### Risk: The new coordinator duplicates part of `SyncEngine` temporarily

Mitigation: keep the extracted layer narrowly focused on target selection, config validation, and upload dispatch. Do not move sync-specific dedupe or state logic into it.

### Risk: Partial-success messaging becomes inconsistent across the UI

Mitigation: centralize message generation in the share upload service or coordinator result mapper rather than rebuilding strings in widgets.

### Risk: Future platform expansion still requires touching multiple files

Mitigation: keep each platform uploader isolated and keep platform registration localized in the coordinator so new targets add one uploader plus one registration step rather than new branches throughout the share flow.
