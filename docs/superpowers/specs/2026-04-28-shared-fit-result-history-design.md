# Design: Shared FIT Result Status And History

**Date:** 2026-04-28  
**Status:** Draft  
**Scope:** Refine shared FIT upload result presentation so partial success is explicit, and persist shared FIT uploads into sync history using the existing history model.

**Prerequisite:** This follow-up builds on the multi-platform shared FIT upload work introduced on the `feature/shared-fit-multi-platform-upload` branch (`Add multi-platform shared FIT uploads`). If that branch is not yet merged, this spec should be applied on top of that branch/worktree rather than against an older Strava-only baseline.

## Goal

When a user shares a FIT file into WanSync and the enabled target platforms do not all end in the same outcome, the result UI should say so clearly.

In particular:

- if all enabled targets succeed or are already uploaded, show a full-success result,
- if some enabled targets succeed or are already uploaded while others fail, show a partial-success result,
- if all enabled targets fail, show a failure result.

Shared FIT uploads should also be written into the existing sync history so the user can review which platforms succeeded, failed, or were already uploaded.

## Current State

The current shared FIT flow already tracks per-platform results internally:

- `FitUploadCoordinatorResult.platformResults` preserves a result per enabled platform,
- `SharedFitUploadService` converts aggregate coordinator results into top-level share upload messages,
- `SharedFitUploadService` currently maps `FitUploadCoordinatorStatus.partialSuccess` into top-level `SharedFitUploadStatus.success`,
- `ShareConfirmScreen` therefore still shows the generic success title for mixed outcomes.

The current history model is already capable of expressing the needed detail:

- `SyncRecord` stores a list of `PlatformSyncResult`,
- `PlatformSyncResult` already supports `success`, `failed`, and `deduped`,
- `SyncHistoryScreen` already renders per-platform status chips and messages.

The missing piece is that the shared FIT upload path does not currently save any `SyncRecord` into `StateStore`.

For users with no enabled upload targets, the current shared FIT flow already routes to missing-configuration handling rather than attempting upload. That behavior should remain unchanged and should not create a history record, because no platform attempt occurred.

## Chosen Approach

Keep the existing share upload coordination and history data models, and add a focused mapping layer that:

1. exposes partial success explicitly in the shared FIT result UI state,
2. converts shared FIT platform outcomes into `PlatformSyncResult`,
3. saves a `SyncRecord` for each completed shared FIT upload.

This is the smallest change that makes the user-visible outcome accurate and reuses the existing history system without forcing the shared FIT flow into `SyncEngine`.

## Why This Approach

- It preserves the existing multi-platform coordinator and uploader boundaries.
- It reuses the already-shipped sync history data model instead of creating a second history format for shared uploads.
- It avoids changing how the main sync engine computes dedupe, persistence, and summary accounting.
- It makes the shared FIT result UI more truthful without overhauling the entire share flow.

## Alternatives Considered

### 1. Only change the share result copy

Rejected because it would improve the immediate screen but still lose the result after the user dismisses it.

### 2. Save a separate shared-upload history format

Rejected because `SyncRecord` and `PlatformSyncResult` already fit the problem, and a second history shape would complicate filtering and rendering.

### 3. Route shared FIT uploads through `SyncEngine`

Rejected because `SyncEngine` still owns OneLap-specific responsibilities that do not belong to the shared local FIT flow.

## Execution Design

### Shared Result State

Add an explicit partial-success path to the shared FIT service/screen contract.

For the share UI, the effective result categories should be:

- full success,
- partial success,
- failure,
- invalid file,
- missing configuration,
- share intake error.

This does not require changing the coordinator aggregate rules. `alreadyUploaded` should continue to count as a successful platform-level outcome.

What changes is the final shared FIT screen mapping:

- all platform results are success-like (`success` or `alreadyUploaded`) -> title `上传成功`
- some platform results are success-like and some are failures -> title `部分成功`
- all platform results are failures -> title `上传失败`

### Shared Result Copy

The body text should continue to list platform-level outcomes explicitly.

Examples:

- `已上传到 Strava 和行者。`
- `Strava已存在；行者上传成功。`
- `Strava已存在；行者上传失败：session expired`
- `Strava上传失败：duplicate poll timeout；行者上传失败：session expired`

The title should summarize the aggregate state, while the body should preserve platform detail.

### History Persistence For Shared Uploads

After a shared FIT upload completes with either:

- full success,
- partial success,
- full failure,

the share flow should write a `SyncRecord` into `StateStore`.

The shared FIT path should not skip history persistence just because one or more platforms failed. The user explicitly asked to see these uploads in history, and mixed or failed outcomes are part of that history.

If no upload target is enabled, or enabled-target configuration is incomplete and the flow stops in missing-configuration state before any platform attempt begins, no history record should be written.

### History Record Mapping

Map shared FIT upload results into the existing history model as follows:

- coordinator `success` -> `PlatformSyncResult(status: SyncStatus.success)`
- coordinator `alreadyUploaded` -> `PlatformSyncResult(status: SyncStatus.deduped)`
- coordinator `failure` -> `PlatformSyncResult(status: SyncStatus.failed)`

Field mapping:

- `sourceFilename`: shared draft display name when available, otherwise file basename
- `startTime`: prefer parsed FIT activity start time; otherwise use a stable fallback derived from the shared local file, such as file last-modified time normalized to ISO8601
- `syncedAt`: current timestamp
- `distanceM`, `ascentM`, `sport`: populate from FIT session metadata when available
- `uploadedToStrava`, `uploadedToXingzhe`: reflect which platforms were enabled in the upload plan
- `platformResults`: the mapped list described above

For shared FIT uploads, `fingerprint` may remain empty unless a stable fingerprint is already available without pulling in unrelated dedupe logic. The current `StateStore` history identity fallback already supports empty fingerprints via `startTime + sourceFilename`, so the fallback `startTime` used here must be stable enough to avoid creating duplicate history entries for retries of the same shared draft.

### FIT Metadata Extraction

Reuse the existing FIT parsing helper in `fit_coordinate_rewrite_service.dart` for `distanceM`, `ascentM`, and `sport`, and extend it or add a sibling helper in the same file to expose FIT activity start time for shared-upload history mapping.

This keeps shared FIT history entries useful in `SyncHistoryScreen` without introducing new parsing logic.

If metadata parsing fails, history persistence should still succeed with fallback values.

### History Screen Compatibility

No structural changes should be required in `SyncHistoryScreen` if the shared upload record reuses `SyncRecord` and `PlatformSyncResult` correctly.

At most, this task may need a small presentational tweak if the shared-upload fallback values expose an awkward label, but no separate shared-history UI should be introduced.

## Testing Design

Follow TDD for the behavior change.

### Shared FIT Upload Service Tests

Add or update tests for:

- partial success maps to a distinct share result category used by the UI,
- full success still maps to the current success category,
- `alreadyUploaded + success` produces a partial/full-success message with platform detail,
- full failure persists a history record with per-platform failed results,
- partial success persists a history record with mixed platform results,
- `alreadyUploaded` maps to `SyncStatus.deduped` in the history record,
- metadata parsing failure still allows history persistence with fallback values.

### Share Confirmation Screen Tests

Add or update tests for:

- partial success title shows `部分成功`,
- full success title remains `上传成功`,
- failure title remains `上传失败`,
- body text continues to show platform-level detail.

### History Tests

Add focused tests for whichever layer persists the shared FIT history entry:

- shared FIT uploads are saved via `StateStore.saveSyncRecords()`,
- saved records appear in `loadSyncRecords()`,
- a mixed-outcome shared upload keeps both platform results.

If `SyncHistoryScreen` already renders the reused data correctly, a dedicated widget change may not be necessary.

### Verification Commands

After implementation, run the narrowest scopes first, then broad verification:

```bash
flutter test test/services/shared_fit_upload_service_test.dart
flutter test test/screens/share_confirm_screen_test.dart
flutter test
flutter analyze
```

## Files Expected To Change

| File | Change |
|---|---|
| `lib/services/shared_fit_upload_service.dart` | Add partial-success UI mapping and persist shared FIT uploads into `StateStore` |
| `lib/screens/share_confirm_screen.dart` | Show `部分成功` title for mixed outcomes while keeping platform detail in the body |
| `lib/services/state_store.dart` | Reuse existing save/load behavior; no structural change expected unless a small helper becomes necessary |
| `lib/services/fit_coordinate_rewrite_service.dart` | Reuse existing FIT metadata parsing helper; no structural change expected |
| `test/services/shared_fit_upload_service_test.dart` | Add regression coverage for partial success, history persistence, and shared-upload record mapping |
| `test/screens/share_confirm_screen_test.dart` | Verify title/body behavior for full success, partial success, and failure |
| `test/services/state_store_test.dart` or a new focused shared-history test file | Verify shared-upload history persistence and merge behavior if needed |

## Non-Goals

- refactoring `SyncEngine` to absorb shared FIT history persistence,
- changing the main sync banner system,
- adding a separate shared-upload history page,
- introducing dedupe or fingerprint persistence for shared local FIT uploads unless needed for the existing history identity fallback.

## Risks And Mitigations

### Risk: Shared-upload history entries look incomplete when FIT metadata is unavailable

Mitigation: use best-effort metadata extraction, but always persist the record with fallback values so the history still reflects what happened.

### Risk: Partial success becomes inconsistent between title and body

Mitigation: centralize aggregate-title and body-message mapping in the shared FIT service/screen contract instead of rebuilding platform summaries in multiple places.

### Risk: Shared-upload history records collide when fingerprints are absent

Mitigation: continue to rely on the existing `StateStore` fallback history identity of `startTime + sourceFilename`, and ensure the shared FIT record mapping uses stable fallback values.
