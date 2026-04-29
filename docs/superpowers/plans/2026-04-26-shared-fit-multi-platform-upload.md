# Shared FIT Multi-Platform Upload Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make system-shared FIT uploads follow the enabled upload targets in Settings and establish a reusable multi-platform upload coordination layer.

**Architecture:** Keep the Android share-entry flow intact, but split platform selection and upload dispatch out of `SharedFitUploadService` into a new coordinator plus focused per-platform uploaders. Implement the change test-first: add coordinator tests, then adapt the share upload service and share confirmation UI to use preflight target metadata and aggregated upload results.

**Tech Stack:** Flutter, Dart, flutter_test, Dio, flutter_secure_storage

---

### File Structure

**Create:**
- `lib/services/fit_upload_coordinator.dart` - resolves enabled upload targets from settings, validates required configuration, runs enabled platform uploads, and returns structured per-platform results plus preflight metadata.
- `lib/services/strava_fit_uploader.dart` - wraps `StravaClient` upload and poll behavior into a platform-agnostic uploader contract.
- `lib/services/xingzhe_fit_uploader.dart` - wraps `XingzheClient` upload and poll behavior into the same uploader contract, including session reuse and login fallback.
- `test/services/fit_upload_coordinator_test.dart` - regression coverage for target resolution, config validation, sequential continuation, and aggregate result behavior.
- `test/services/strava_fit_uploader_test.dart` - focused regression coverage for Strava uploader success, duplicate, and incomplete-upload normalization.
- `test/services/xingzhe_fit_uploader_test.dart` - focused regression coverage for Xingzhe session reuse, login fallback, and duplicate normalization.

**Modify:**
- `lib/services/shared_fit_upload_service.dart` - keep FIT validation and GCJ rewrite local, add preflight support, delegate target decisions to the coordinator, and map aggregate results to user-visible messages.
- `lib/screens/share_confirm_screen.dart` - replace Strava-only wording with preflight-driven target labels and aggregated success/missing-config messages.
- `lib/services/share_navigation_coordinator.dart` - pass the updated share upload service interface through to the confirmation screen if constructor shape changes.
- `lib/main.dart` - wire the updated `SharedFitUploadService` dependencies if the default constructor changes.
- `test/services/shared_fit_upload_service_test.dart` - replace Strava-only executor tests with coordinator delegation tests and target-aware assertions.
- `test/screens/share_confirm_screen_test.dart` - verify target-specific button labels and result copy.

### Task 1: Add coordinator-first regression coverage

**Files:**
- Create: `test/services/fit_upload_coordinator_test.dart`
- Create: `lib/services/fit_upload_coordinator.dart`

- [ ] **Step 1: Define the coordinator contract in the test file before writing production code**

In `test/services/fit_upload_coordinator_test.dart`, sketch the intended public API with fake uploaders and a minimal result contract. Keep the planned types focused on this task:

```dart
enum FitUploadPlatform { strava, xingzhe }

enum FitUploadPlatformStatus { success, alreadyUploaded, failure }

class FitUploadPlatformResult {
  final FitUploadPlatform platform;
  final FitUploadPlatformStatus status;
  final String? message;
}

class FitUploadPlan {
  final List<FitUploadPlatform> targets;
  final bool hasMissingConfiguration;
  final String targetLabel;
}
```

Use fakes that record calls and can return either success, already-uploaded, or failure results.

Use `SettingsService.keyUploadToStrava` and `SettingsService.keyUploadToXingzhe` in every settings fixture instead of hard-coded string keys so the coordinator and tests share the same source of truth.

- [ ] **Step 2: Write the failing coordinator tests**

Add tests covering:
- Strava-only settings call only the Strava uploader.
- Xingzhe-only settings call only the Xingzhe uploader.
- Both toggles enabled call both uploaders in order.
- Values like `TRUE` and ` true ` are treated as enabled.
- No enabled targets produces a preflight plan with `hasMissingConfiguration == true` and no upload attempts.
- Strava enabled with missing Strava credentials blocks upload before any uploader runs.
- Xingzhe enabled with missing Xingzhe credentials blocks upload before any uploader runs.
- Both enabled with missing Xingzhe credentials blocks upload before any uploader runs.
- Strava failure still allows Xingzhe to run.
- `alreadyUploaded` counts toward aggregate success.
- All failed attempts produce an aggregate failure result.

Example assertion shape:

```dart
expect(result.platformResults.map((r) => r.platform), <FitUploadPlatform>[
  FitUploadPlatform.strava,
  FitUploadPlatform.xingzhe,
]);
expect(fakeStrava.calls, 1);
expect(fakeXingzhe.calls, 1);
```

- [ ] **Step 3: Run the new coordinator tests to verify they fail**

Run: `flutter test test/services/fit_upload_coordinator_test.dart`

Expected: FAIL because `fit_upload_coordinator.dart` and the tested contract do not exist yet.

- [ ] **Step 4: Implement the minimal coordinator and result types**

Create `lib/services/fit_upload_coordinator.dart` with:
- enums for platform identifiers and platform result status,
- a `FitUploadPlan` preflight model,
- a `FitUploadCoordinatorResult` aggregate model,
- a small uploader interface such as `FitPlatformUploader`,
- `resolveUploadPlan(Map<String, String> settings)`,
- `uploadFile(File file, Map<String, String> settings)`.

Keep configuration validation inside the coordinator. Use helpers like:

```dart
bool _isEnabled(Map<String, String> settings, String key) {
  return (settings[key] ?? '').trim().toLowerCase() == 'true';
}

bool _hasValue(Map<String, String> settings, String key) {
  return (settings[key] ?? '').trim().isNotEmpty;
}
```

Catch uploader exceptions per platform, convert them to `failure` platform results, and continue to the next enabled target.

- [ ] **Step 5: Run the coordinator tests to verify they pass**

Run: `flutter test test/services/fit_upload_coordinator_test.dart`

Expected: PASS

### Task 2: Add concrete Strava and Xingzhe uploaders

**Files:**
- Create: `lib/services/strava_fit_uploader.dart`
- Create: `lib/services/xingzhe_fit_uploader.dart`
- Modify: `lib/services/fit_upload_coordinator.dart`
- Test: `test/services/fit_upload_coordinator_test.dart`

### Task 2A: Add focused uploader regression tests

**Files:**
- Create: `test/services/strava_fit_uploader_test.dart`
- Create: `test/services/xingzhe_fit_uploader_test.dart`
- Create: `lib/services/strava_fit_uploader.dart`
- Create: `lib/services/xingzhe_fit_uploader.dart`

- [ ] **Step 1: Write the failing Strava uploader tests**

Read these files first so the wrapper tests preserve existing behavior rather than inventing a new contract:
- `lib/services/strava_client.dart`
- `lib/services/xingzhe_client.dart`
- `lib/services/sync_engine.dart`

In `test/services/strava_fit_uploader_test.dart`, cover the wrapper responsibilities that the coordinator cannot prove by itself:
- poll result with `activity_id` returns `success`,
- poll result with duplicate wording returns `alreadyUploaded`,
- poll result with neither `activity_id` nor duplicate wording fails as an incomplete upload.

Example assertion shape:

```dart
expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
expect(result.message, contains('duplicate'));
```

- [ ] **Step 2: Write the failing Xingzhe uploader tests**

In `test/services/xingzhe_fit_uploader_test.dart`, cover:
- existing `XINGZHE_SESSION_ID` is reused when present,
- uploader can proceed with username/password when session ID is absent,
- duplicate/idempotent Xingzhe response normalizes to `alreadyUploaded`.

Use fake client factories so the tests control whether the wrapper reuses an existing client or logs in again.

- [ ] **Step 3: Run the new uploader tests to verify they fail**

Run: `flutter test test/services/strava_fit_uploader_test.dart test/services/xingzhe_fit_uploader_test.dart`

Expected: FAIL because the uploader wrapper files do not exist yet.

- [ ] **Step 4: Implement the minimal uploader wrappers**

In `lib/services/strava_fit_uploader.dart`:
- build `StravaClient` from settings,
- call `uploadFit()` then `pollUpload()`,
- return `success` when `activity_id` is present,
- return `alreadyUploaded` when the poll result contains duplicate/idempotent wording,
- throw or return a failure-shaped result for incomplete uploads.

In `lib/services/xingzhe_fit_uploader.dart`:
- prefer `XINGZHE_SESSION_ID` if present,
- allow login with username/password when the session is missing or stale,
- normalize duplicate behavior such as code `9006` into `alreadyUploaded`.

- [ ] **Step 5: Run the uploader tests to verify they pass**

Run: `flutter test test/services/strava_fit_uploader_test.dart test/services/xingzhe_fit_uploader_test.dart`

Expected: PASS

- [ ] **Step 6: Add a failing coordinator integration test that uses the concrete uploader defaults**

Extend `test/services/fit_upload_coordinator_test.dart` with one test that proves the coordinator treats `alreadyUploaded` from a concrete uploader result as aggregate success:

```dart
expect(result.hasSuccessfulUpload, isTrue);
expect(
  result.platformResults.single.status,
  FitUploadPlatformStatus.alreadyUploaded,
);
```

- [ ] **Step 7: Run the focused coordinator test to verify it fails**

Run: `flutter test test/services/fit_upload_coordinator_test.dart`

Expected: FAIL because the coordinator is not yet wired to use the concrete uploader defaults.

- [ ] **Step 8: Wire the coordinator defaults to the concrete uploaders**

Wire the coordinator defaults to these uploader implementations.

- [ ] **Step 9: Re-run the focused coordinator test**

Run: `flutter test test/services/fit_upload_coordinator_test.dart`

Expected: PASS

### Task 3: Convert `SharedFitUploadService` to preflight + coordinator delegation

**Files:**
- Modify: `lib/services/shared_fit_upload_service.dart`
- Modify: `test/services/shared_fit_upload_service_test.dart`
- Modify: `lib/services/fit_upload_coordinator.dart`

- [ ] **Step 1: Write failing tests for the new share-service contract**

In `test/services/shared_fit_upload_service_test.dart`, replace the Strava-only executor assumptions with coordinator-based expectations.

Add or update tests for:
- preflight target label returns `Strava`, `行者`, or `Strava 和行者`,
- no enabled targets maps to `missingConfiguration`,
- GCJ rewrite still happens before upload delegation,
- rewritten temp files are deleted after the delegated upload attempt,
- one platform success and one platform failure returns top-level `success` with a partial-success message,
- unreadable and invalid files still return `invalidFile` before preflight/upload.

Use a fake coordinator shaped like:

```dart
class _FakeFitUploadCoordinator extends FitUploadCoordinator {
  FitUploadPlan plan = const FitUploadPlan(...);
  FitUploadCoordinatorResult result = const FitUploadCoordinatorResult(...);
}
```

- [ ] **Step 2: Run the share-service tests to verify they fail**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`

Expected: FAIL because `SharedFitUploadService` does not yet expose preflight metadata or call the coordinator.

- [ ] **Step 3: Implement the minimal share-service changes**

Refactor `lib/services/shared_fit_upload_service.dart` to:
- accept a `FitUploadCoordinator` dependency instead of `executeUpload`,
- expose a preflight method such as `loadUploadPlan()` or `resolveDraftPlan()`,
- keep file validation and rewrite logic inside the service,
- call `coordinator.uploadFile()` after rewrite,
- map aggregate platform results back to `SharedFitUploadResult`,
- generate the user-facing success and partial-success message in one place.

Preserve the existing cleanup pattern:

```dart
try {
  final result = await _coordinator.uploadFile(uploadFile, settings);
  ...
} finally {
  if (shouldDeleteUploadFile) {
    await _deleteTempUploadFile(uploadFile);
  }
}
```

- [ ] **Step 4: Run the share-service tests to verify they pass**

Run: `flutter test test/services/shared_fit_upload_service_test.dart`

Expected: PASS

### Task 4: Update the share confirmation UI and run verification

**Files:**
- Modify: `lib/screens/share_confirm_screen.dart`
- Modify: `lib/services/share_navigation_coordinator.dart`
- Modify: `lib/main.dart`
- Modify: `test/screens/share_confirm_screen_test.dart`
- Verify only: changed files above and new service files

- [ ] **Step 1: Write failing widget tests for target-aware wording**

Update `test/screens/share_confirm_screen_test.dart` so the fake upload service can provide both a preflight plan and an upload result.

Add tests for:
- confirm button says `上传到 Strava` when only Strava is enabled,
- confirm button says `上传到行者` when only Xingzhe is enabled,
- confirm button says `上传到 Strava 和行者` when both are enabled,
- success copy still supports Strava-only success wording,
- success copy supports Xingzhe-only success wording,
- success copy supports dual-platform success wording,
- missing-config copy references the enabled targets instead of always Strava,
- partial-success upload shows a mixed outcome message,
- success screen uses the service-provided success message.

Example assertion shape:

```dart
expect(find.text('上传到 Strava 和行者'), findsOneWidget);
expect(find.text('已上传到 Strava；行者上传失败：session expired'), findsOneWidget);
```

- [ ] **Step 2: Run the widget tests to verify they fail**

Run: `flutter test test/screens/share_confirm_screen_test.dart`

Expected: FAIL because `ShareConfirmScreen` still contains fixed Strava-only text.

- [ ] **Step 3: Implement the minimal UI wiring**

Update `ShareConfirmScreen` to load the preflight target metadata during `initState()` for draft events and use it to render button and missing-config text.

Keep the control flow simple:
- draft event: show target-aware confirmation copy,
- error event: continue to render the error-only state,
- upload success/failure: display the mapped message returned by `SharedFitUploadService`.

If constructor or initialization changes require passing a differently configured upload service, make the smallest matching updates in `share_navigation_coordinator.dart` and `main.dart`.

- [ ] **Step 4: Run the widget tests to verify they pass**

Run: `flutter test test/screens/share_confirm_screen_test.dart`

Expected: PASS

- [ ] **Step 5: Format changed Dart files**

Run: `dart format lib test`

Expected: formatting completes without errors.

- [ ] **Step 6: Run the full relevant test suite**

Run: `flutter test`

Expected: all tests pass.

- [ ] **Step 7: Run analyzer**

Run: `flutter analyze`

Expected: no new analysis issues.
