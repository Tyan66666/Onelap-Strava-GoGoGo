# Shared FIT Result And History Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shared FIT uploads show `部分成功` for mixed platform outcomes and persist shared-upload results into sync history using the existing `SyncRecord` model.

**Architecture:** Keep the existing multi-platform shared-upload coordinator intact and make the smallest possible changes in the shared upload service and share confirmation UI. Reuse `SyncRecord`, `PlatformSyncResult`, and `StateStore.saveSyncRecords()` for history persistence, and extend FIT metadata parsing just enough to expose activity start time for shared-upload records.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing `fit_tool` parsing via `fit_coordinate_rewrite_service.dart`

---

## File Map

- Modify: `lib/services/shared_fit_upload_service.dart`
  Responsibility: map coordinator aggregate results into explicit shared-upload UI states, build shared-upload history records, and save them through `StateStore`.
- Modify: `lib/screens/share_confirm_screen.dart`
  Responsibility: render the correct result title for full success, partial success, and failure while keeping existing body-detail rendering.
- Modify: `lib/services/fit_coordinate_rewrite_service.dart`
  Responsibility: expose FIT activity start time alongside existing session metadata needed for history records.
- Modify: `test/services/shared_fit_upload_service_test.dart`
  Responsibility: cover shared-upload result mapping, history persistence, and FIT metadata fallback behavior.
- Modify: `test/screens/share_confirm_screen_test.dart`
  Responsibility: verify result titles and body content for success, partial success, and failure.
- Modify if needed: `test/services/state_store_test.dart`
  Responsibility: add coverage only if shared-upload persistence needs a direct regression test beyond service-level tests.

### Task 1: Extend FIT Metadata Parsing For History Records

**Files:**
- Modify: `lib/services/fit_coordinate_rewrite_service.dart`
- Test: `test/services/shared_fit_upload_service_test.dart`

- [ ] **Step 1: Write the failing test for FIT start time extraction**

Add a focused test in `test/services/shared_fit_upload_service_test.dart` that exercises shared-upload history mapping with parsed FIT metadata and expects the resulting `SyncRecord.startTime` to come from the FIT activity/session start time, not from `DateTime.now()`.

- [ ] **Step 2: Run the targeted test to verify it fails**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: FAIL because the current metadata helper does not expose start time into shared-upload history mapping.

- [ ] **Step 3: Extend FIT metadata parsing minimally**

Update `lib/services/fit_coordinate_rewrite_service.dart` so `FitSessionMeta` also carries `startTime`, parsed from the first relevant FIT session/activity timestamp. Keep the helper best-effort: if parsing fails, return an empty field without throwing.

- [ ] **Step 4: Re-run the targeted test to verify it passes**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: PASS for the new metadata assertion, with existing tests still green.

- [ ] **Step 5: Commit the metadata helper change**

```bash
git add lib/services/fit_coordinate_rewrite_service.dart test/services/shared_fit_upload_service_test.dart
git commit -m "Expose FIT start time for shared history"
```

### Task 2: Add Explicit Partial-Success Shared Upload State

**Files:**
- Modify: `lib/services/shared_fit_upload_service.dart`
- Modify: `test/services/shared_fit_upload_service_test.dart`

- [ ] **Step 1: Write failing service tests for aggregate result mapping**

Add service tests that cover:

- `FitUploadCoordinatorStatus.partialSuccess` mapping to a distinct shared-upload result state,
- all-success/all-already-uploaded mapping to `success`,
- all-failure mapping to `failure`,
- body text continuing to preserve per-platform detail.

- [ ] **Step 2: Run the targeted test file to verify failure**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: FAIL because `SharedFitUploadStatus` currently has no explicit partial-success state.

- [ ] **Step 3: Implement the minimal service change**

Update `lib/services/shared_fit_upload_service.dart` to:

- add a `partialSuccess` enum case,
- map coordinator aggregate results into `success`, `partialSuccess`, or `failure` correctly,
- keep `alreadyUploaded` as a success-like platform result,
- keep existing invalid-file and missing-configuration behavior unchanged.

- [ ] **Step 4: Re-run the targeted tests**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: PASS for the new aggregate-result coverage.

- [ ] **Step 5: Commit the service-state change**

```bash
git add lib/services/shared_fit_upload_service.dart test/services/shared_fit_upload_service_test.dart
git commit -m "Differentiate partial shared upload success"
```

### Task 3: Persist Shared Upload Results Into Sync History

**Files:**
- Modify: `lib/services/shared_fit_upload_service.dart`
- Modify: `test/services/shared_fit_upload_service_test.dart`
- Modify if needed: `test/services/state_store_test.dart`

- [ ] **Step 1: Write failing tests for history persistence**

Add service tests covering:

- partial success writes one `SyncRecord` with mixed `platformResults`,
- full failure still writes one `SyncRecord` with failed platform statuses,
- `alreadyUploaded` maps to `SyncStatus.deduped`,
- missing-configuration / no-attempt flows do not write history,
- metadata parse failure falls back to a stable non-empty `startTime` source for history identity.

Use injected dependencies or test doubles instead of real file-system state where possible.

- [ ] **Step 2: Run the targeted tests to verify failure**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: FAIL because shared-upload history persistence does not exist yet.

- [ ] **Step 3: Implement minimal history persistence in the service**

Update `lib/services/shared_fit_upload_service.dart` to:

- load FIT metadata once for history mapping,
- convert coordinator platform results into `PlatformSyncResult`,
- build a `SyncRecord` with `sourceFilename`, parsed `startTime`, `syncedAt`, metadata fields, enabled-target booleans, and per-platform results,
- call `StateStore.saveSyncRecords()` only for completed attempt outcomes (`success`, `partialSuccess`, `failure`),
- avoid writing history for invalid-file or missing-configuration outcomes,
- use a stable fallback for `startTime` only when FIT parsing fails.

- [ ] **Step 4: Re-run targeted tests**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`
Expected: PASS for history persistence scenarios.

- [ ] **Step 5: Add direct state-store regression coverage only if needed**

If the service tests already prove saved shared-upload records round-trip through `StateStore`, skip extra state-store tests. Otherwise add the smallest focused regression in `test/services/state_store_test.dart` and run only that file.

- [ ] **Step 6: Commit the history persistence change**

```bash
git add lib/services/shared_fit_upload_service.dart test/services/shared_fit_upload_service_test.dart test/services/state_store_test.dart
git commit -m "Save shared uploads to sync history"
```

### Task 4: Update Share Result UI Titles

**Files:**
- Modify: `lib/screens/share_confirm_screen.dart`
- Modify: `test/screens/share_confirm_screen_test.dart`

- [ ] **Step 1: Write failing widget tests for result titles**

Add widget tests that verify:

- `SharedFitUploadStatus.partialSuccess` shows `部分成功`,
- `SharedFitUploadStatus.success` still shows `上传成功`,
- `SharedFitUploadStatus.failure` still shows `上传失败`,
- platform detail text remains visible in the result body.

- [ ] **Step 2: Run the widget test file to verify failure**

Run: `flutter test test/screens/share_confirm_screen_test.dart`
Expected: FAIL because the screen does not yet distinguish partial success in its title mapping.

- [ ] **Step 3: Implement the minimal UI update**

Update `lib/screens/share_confirm_screen.dart` so the title mapping reflects the new explicit `partialSuccess` state without changing unrelated share-intake or preflight behavior.

- [ ] **Step 4: Re-run the widget tests**

Run: `flutter test test/screens/share_confirm_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit the UI change**

```bash
git add lib/screens/share_confirm_screen.dart test/screens/share_confirm_screen_test.dart
git commit -m "Show partial success for shared uploads"
```

### Task 5: Run Full Verification

**Files:**
- Modify only if verification reveals issues: the files above

- [ ] **Step 1: Run focused tests in sequence**

Run:

```bash
flutter test test/services/shared_fit_upload_service_test.dart
flutter test test/screens/share_confirm_screen_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`
Expected: PASS with no new warnings/errors introduced by this change.

- [ ] **Step 4: Fix any failures and rerun the narrowest affected verification**

If any command fails, make the smallest corrective change and rerun the impacted file/test first, then rerun the full verification sequence.

- [ ] **Step 5: Commit the verification-clean final state**

```bash
git add lib/services/shared_fit_upload_service.dart lib/services/fit_coordinate_rewrite_service.dart lib/screens/share_confirm_screen.dart test/services/shared_fit_upload_service_test.dart test/screens/share_confirm_screen_test.dart test/services/state_store_test.dart
git commit -m "Finalize shared upload result history flow"
```

## Notes

- Do not refactor `SyncEngine` for this task.
- Do not introduce a separate shared-upload history page.
- Keep history persistence additive and reuse existing `SyncRecord` / `PlatformSyncResult` structures.
- Prefer injecting dependencies in tests over touching real app documents storage unless a direct `StateStore` round-trip is the specific thing under test.
