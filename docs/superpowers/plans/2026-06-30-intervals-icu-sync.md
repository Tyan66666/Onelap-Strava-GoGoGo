# Intervals.icu 同步功能 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Intervals.icu as a third sync destination platform alongside Strava and Xingzhe, and refactor the settings page into a main page + platform sub-pages.

**Architecture:** Follow the existing pattern — create `IntervalsIcuClient` (Dio + Basic Auth + POST multipart), add `_uploadToIntervalsIcu()` helper in `SyncEngine`, create `IntervalsIcuFitUploader` implementing `FitPlatformUploader`, update all models to include `intervalsIcu` platform, and refactor settings into sub-screens.

**Tech Stack:** Dart/Flutter, Dio (HTTP), flutter_secure_storage (credentials), existing model/service patterns

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `lib/services/intervals_icu_client.dart` | Intervals.icu API client — upload FIT files |
| Create | `lib/services/intervals_icu_fit_uploader.dart` | FitPlatformUploader implementation for single-file share upload |
| Create | `lib/screens/intervals_icu_settings_screen.dart` | Intervals.icu settings sub-page |
| Create | `lib/screens/strava_settings_screen.dart` | Strava settings sub-page (extracted from SettingsScreen) |
| Create | `lib/screens/xingzhe_settings_screen.dart` | Xingzhe settings sub-page (extracted from SettingsScreen) |
| Create | `test/services/intervals_icu_client_test.dart` | IntervalsIcuClient unit tests |
| Create | `test/services/intervals_icu_fit_uploader_test.dart` | IntervalsIcuFitUploader unit tests |
| Modify | `lib/services/settings_service.dart` | Add INTERVALS_ICU_ATHLETE_ID, INTERVALS_ICU_API_KEY, UPLOAD_TO_INTERVALS_ICU keys |
| Modify | `lib/services/sync_engine.dart` | Add IntervalsIcuClient param, `_uploadToIntervalsIcu()` helper, parallel upload |
| Modify | `lib/services/fit_upload_coordinator.dart` | Add `intervalsIcu` to enum, IntervalsIcuUploader, update plan/resolver |
| Modify | `lib/models/sync_record.dart` | Add `intervalsIcu` to `SyncPlatform` enum |
| Modify | `lib/models/sync_progress.dart` | Add `intervalsIcuUploaded`, `intervalsIcuEnabled` fields |
| Modify | `lib/models/sync_summary.dart` | Add `intervalsIcuSuccess/Failed/Deduped/Failures` fields |
| Modify | `lib/models/sync_result_banner.dart` | Add intervalsIcu data, fix "已通过" → "已跳过" |
| Modify | `lib/screens/settings_screen.dart` | Refactor to main page with platform cards + sub-page navigation |
| Modify | `lib/screens/home_screen.dart` | Add Intervals.icu progress bar, result chips, credential validation |
| Modify | `test/models/sync_record_test.dart` | Add intervalsIcu serialization tests |
| Modify | `test/models/sync_progress_test.dart` | Add intervalsIcu field tests |
| Modify | `test/models/sync_result_banner_test.dart` | Add intervalsIcu tests |
| Modify | `test/services/sync_engine_test.dart` | Add Intervals.icu upload tests |
| Modify | `test/services/fit_upload_coordinator_test.dart` | Add Intervals.icu platform tests |
| Modify | `test/screens/home_screen_test.dart` | Update for new UI elements |
| Modify | `test/screens/settings_screen_test.dart` | Update for refactored settings |

---

### Task 1: SettingsService — Add Intervals.icu Keys

**Files:**
- Modify: `lib/services/settings_service.dart:55-77`

- [ ] **Step 1: Add key constants**

Add after line 58 (`keyUploadToXingzhe`):

```dart
static const keyIntervalsIcuAthleteId = 'INTERVALS_ICU_ATHLETE_ID';
static const keyIntervalsIcuApiKey = 'INTERVALS_ICU_API_KEY';
static const keyUploadToIntervalsIcu = 'UPLOAD_TO_INTERVALS_ICU';
```

- [ ] **Step 2: Add keys to allKeys list**

Add to the `allKeys` list (after `keyUploadToXingzhe`):

```dart
keyIntervalsIcuAthleteId,
keyIntervalsIcuApiKey,
keyUploadToIntervalsIcu,
```

- [ ] **Step 3: Verify StateStore compatibility**

`StateStore` already accepts arbitrary platform strings (it stores them as JSON map keys in `state.json`). The methods `isAlreadyUploaded(fingerprint, platform)`, `markPlatformSynced(fingerprint, platform, remoteId)`, `getRemoteActivityId(fingerprint, platform)`, and `clearPlatformStatus(fingerprint, platform)` all take `String platform` — no code changes needed. Verify by reading `lib/services/state_store.dart` and confirming the platform parameter is a plain `String`.

- [ ] **Step 4: Run tests to verify no breakage**

Run: `flutter test test/services/settings_service_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/services/settings_service.dart
git commit -m "feat: add Intervals.icu settings keys"
```

---

### Task 2: SyncRecord — Add intervalsIcu Platform

**Files:**
- Modify: `lib/models/sync_record.dart:1`
- Modify: `test/models/sync_record_test.dart`

- [ ] **Step 1: Write failing test for intervalsIcu serialization**

Add to `test/models/sync_record_test.dart`:

```dart
test('PlatformSyncResult with intervalsIcu platform serializes/deserializes', () {
  const result = PlatformSyncResult(
    platform: SyncPlatform.intervalsIcu,
    status: SyncStatus.success,
    remoteActivityId: 456,
    syncedAt: '2026-06-30T12:00:00',
  );
  final json = result.toJson();
  expect(json['platform'], 'intervalsIcu');
  final restored = PlatformSyncResult.fromJson(json);
  expect(restored.platform, SyncPlatform.intervalsIcu);
  expect(restored.remoteActivityId, 456);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sync_record_test.dart`
Expected: FAIL — `intervalsIcu` not in enum

- [ ] **Step 3: Add intervalsIcu to SyncPlatform enum**

Change line 1 from:
```dart
enum SyncPlatform { strava, xingzhe }
```
to:
```dart
enum SyncPlatform { strava, xingzhe, intervalsIcu }
```

- [ ] **Step 4: Add uploadedToIntervalsIcu field to SyncRecord**

Add field after `uploadedToXingzhe` (line 77):
```dart
final bool uploadedToIntervalsIcu;
```

Update constructor (line 80) to include `this.uploadedToIntervalsIcu = false`.

Update `toJson()` to include `'uploadedToIntervalsIcu': uploadedToIntervalsIcu`.

Update `fromJson()` to include `uploadedToIntervalsIcu: json['uploadedToIntervalsIcu'] as bool? ?? false`.

Update `copyWith()` to include `bool? uploadedToIntervalsIcu` parameter.

Update `mergeWith()` to include `uploadedToIntervalsIcu: base.uploadedToIntervalsIcu || uploadedToIntervalsIcu`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/models/sync_record_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/models/sync_record.dart test/models/sync_record_test.dart
git commit -m "feat: add intervalsIcu to SyncPlatform enum and SyncRecord"
```

---

### Task 3: SyncProgress — Add intervalsIcu Fields

**Files:**
- Modify: `lib/models/sync_progress.dart`
- Modify: `test/models/sync_progress_test.dart`

- [ ] **Step 1: Write failing test**

Add to `test/models/sync_progress_test.dart`:

```dart
test('SyncProgress includes intervalsIcu fields', () {
  const progress = SyncProgress(
    intervalsIcuEnabled: true,
    intervalsIcuUploaded: 3,
  );
  expect(progress.intervalsIcuEnabled, true);
  expect(progress.intervalsIcuUploaded, 3);
  final copy = progress.copyWith(intervalsIcuUploaded: 5);
  expect(copy.intervalsIcuUploaded, 5);
  expect(copy.intervalsIcuEnabled, true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sync_progress_test.dart`

- [ ] **Step 3: Add fields to SyncProgress**

Add after `xingzheEnabled` (line 8):
```dart
final int intervalsIcuUploaded;
final bool intervalsIcuEnabled;
```

Update constructor defaults:
```dart
this.intervalsIcuUploaded = 0,
this.intervalsIcuEnabled = false,
```

Update `copyWith()`, `==`, `hashCode`, `toString()` to include new fields.

- [ ] **Step 4: Run tests**

Run: `flutter test test/models/sync_progress_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/models/sync_progress.dart test/models/sync_progress_test.dart
git commit -m "feat: add intervalsIcu fields to SyncProgress"
```

---

### Task 4: SyncSummary — Add intervalsIcu Fields

**Files:**
- Modify: `lib/models/sync_summary.dart`

- [ ] **Step 1: Add fields to SyncSummary**

Add after `stravaFailures` (line 59):
```dart
final int intervalsIcuSuccess;
final int intervalsIcuFailed;
final int intervalsIcuDeduped;
final List<FailedActivitySummary> intervalsIcuFailures;
```

Update constructor defaults (all 0 / const []).

Update `bannerTitle` to include intervalsIcu count in the success string if relevant.

- [ ] **Step 2: Run existing tests**

Run: `flutter test test/models/`

- [ ] **Step 3: Commit**

```bash
git add lib/models/sync_summary.dart
git commit -m "feat: add intervalsIcu fields to SyncSummary"
```

---

### Task 5: SyncResultBanner — Add intervalsIcu Data

**Files:**
- Modify: `lib/models/sync_result_banner.dart`

- [ ] **Step 1: Add fields**

Add after `stravaFailures` (line 25):
```dart
// Intervals.icu
final int intervalsIcuSuccess;
final int intervalsIcuFailed;
final int intervalsIcuDeduped;
final List<FailedActivitySummary> intervalsIcuFailures;
```

Update constructor, `fromSyncSummary()`, `toJson()`, `fromJson()`, `toSyncSummary()`.

- [ ] **Step 2: Fix "已通过" → "已跳过"**

Line 119: Change `'$deduped条已通过'` to `'$deduped条已跳过'`.

- [ ] **Step 3: Run tests**

Run: `flutter test test/models/sync_result_banner_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/models/sync_result_banner.dart
git commit -m "feat: add intervalsIcu to SyncResultBanner, fix 已通过→已跳过"
```

---

### Task 6: IntervalsIcuClient — API Client

**Files:**
- Create: `lib/services/intervals_icu_client.dart`
- Create: `test/services/intervals_icu_client_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onelap_strava_sync/services/intervals_icu_client.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late IntervalsIcuClient client;
  late Directory tempDir;

  setUpAll(() {
    registerFallbackValue(FormData.fromMap({}));
    registerFallbackValue(Options());
  });

  setUp(() async {
    mockDio = MockDio();
    client = IntervalsIcuClient(
      athleteId: 'i12345',
      apiKey: 'test-api-key',
      dio: mockDio,
    );
    tempDir = await Directory.systemTemp.createTemp('intervals_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('uploadFit', () {
    test('returns activity id on 201', () async {
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01, 0x02]);
      when(() => mockDio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => Response(
        data: {'id': 789},
        statusCode: 201,
        requestOptions: RequestOptions(path: ''),
      ));
      final result = await client.uploadFit(file);
      expect(result, 789);
    });

    test('treats 200 as success (duplicate)', () async {
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01, 0x02]);
      when(() => mockDio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => Response(
        data: {},
        statusCode: 200,
        requestOptions: RequestOptions(path: ''),
      ));
      final result = await client.uploadFit(file);
      expect(result, 0);
    });

    test('throws IntervalsIcuPermanentError on 401', () async {
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01, 0x02]);
      when(() => mockDio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenThrow(DioException(
        type: DioExceptionType.badResponse,
        response: Response(statusCode: 401, requestOptions: RequestOptions(path: '')),
        requestOptions: RequestOptions(path: ''),
      ));
      expect(() => client.uploadFit(file), throwsA(isA<IntervalsIcuPermanentError>()));
    });

    test('throws IntervalsIcuRetriableError on 5xx', () async {
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01, 0x02]);
      when(() => mockDio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenThrow(DioException(
        type: DioExceptionType.badResponse,
        response: Response(statusCode: 500, requestOptions: RequestOptions(path: '')),
        requestOptions: RequestOptions(path: ''),
      ));
      expect(() => client.uploadFit(file), throwsA(isA<IntervalsIcuRetriableError>()));
    });

    test('throws IntervalsIcuRetriableError on 429', () async {
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01, 0x02]);
      when(() => mockDio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenThrow(DioException(
        type: DioExceptionType.badResponse,
        response: Response(statusCode: 429, requestOptions: RequestOptions(path: '')),
        requestOptions: RequestOptions(path: ''),
      ));
      expect(() => client.uploadFit(file), throwsA(isA<IntervalsIcuRetriableError>()));
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/intervals_icu_client_test.dart`

- [ ] **Step 3: Implement IntervalsIcuClient**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class IntervalsIcuRetriableError implements Exception {
  final String message;
  const IntervalsIcuRetriableError(this.message);
  @override
  String toString() => 'IntervalsIcuRetriableError: $message';
}

class IntervalsIcuPermanentError implements Exception {
  final String message;
  const IntervalsIcuPermanentError(this.message);
  @override
  String toString() => 'IntervalsIcuPermanentError: $message';
}

class IntervalsIcuClient {
  final String athleteId;
  final String apiKey;
  final Dio _dio;

  IntervalsIcuClient({
    required this.athleteId,
    required this.apiKey,
    Dio? dio,
  }) : _dio = dio ?? Dio(BaseOptions(
         connectTimeout: const Duration(seconds: 30),
         receiveTimeout: const Duration(seconds: 30),
       ));

  Future<int> uploadFit(File file, {int retries = 3}) async {
    for (var attempt = 1; attempt <= retries; attempt++) {
      Response response;
      try {
        response = await _dio.post(
          'https://intervals.icu/api/v1/athlete/$athleteId/activities',
          options: Options(
            headers: {
              'Authorization': 'Basic ${_basicAuth()}',
            },
            validateStatus: (status) => status != null && status < 500,
          ),
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(
              file.path,
              filename: file.path.split('/').last,
            ),
          }),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if ((status >= 500 || status == 429) && attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        if (status >= 500 || status == 429) {
          throw IntervalsIcuRetriableError('intervals.icu upload retriable: $status');
        }
        if (status == 401) {
          throw const IntervalsIcuPermanentError('intervals.icu: API Key 无效');
        }
        if (status >= 400) {
          throw IntervalsIcuPermanentError(
            'intervals.icu upload failed: $status',
          );
        }
        rethrow;
      }

      // 201 = new activity, 200 = duplicate (both success)
      final statusCode = response.statusCode ?? 0;
      if (statusCode == 201 || statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return (data['id'] as num?)?.toInt() ?? 0;
        }
        return 0;
      }

      if (statusCode == 401) {
        throw const IntervalsIcuPermanentError('intervals.icu: API Key 无效');
      }
      if (statusCode == 429 || statusCode >= 500) {
        if (attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        throw IntervalsIcuRetriableError('intervals.icu upload retriable: $statusCode');
      }
      if (statusCode >= 400) {
        throw IntervalsIcuPermanentError(
          'intervals.icu upload failed: $statusCode',
        );
      }
    }
    throw const IntervalsIcuRetriableError('intervals.icu upload exhausted retries');
  }

  String _basicAuth() {
    final bytes = utf8.encode('API_KEY:$apiKey');
    return base64.encode(bytes);
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/intervals_icu_client_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/services/intervals_icu_client.dart test/services/intervals_icu_client_test.dart
git commit -m "feat: add IntervalsIcuClient for FIT file upload"
```

---

### Task 7: IntervalsIcuFitUploader — FitUploadCoordinator Integration

**Files:**
- Create: `lib/services/intervals_icu_fit_uploader.dart`
- Create: `test/services/intervals_icu_fit_uploader_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/intervals_icu_client.dart';
import 'package:onelap_strava_sync/services/intervals_icu_fit_uploader.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('intervals_uploader_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('IntervalsIcuFitUploader', () {
    test('returns failure when credentials missing', () async {
      final uploader = IntervalsIcuFitUploader();
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01]);
      final result = await uploader.upload(
        file: file,
        settings: {},
      );
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.message, contains('凭证未配置'));
    });

    test('returns platform intervalsIcu on network error', () async {
      // Verifies the uploader catches errors and returns a proper result
      final uploader = IntervalsIcuFitUploader();
      final file = File('${tempDir}/test.fit');
      await file.writeAsBytes([0x01]);
      final result = await uploader.upload(
        file: file,
        settings: {
          SettingsService.keyIntervalsIcuAthleteId: 'i12345',
          SettingsService.keyIntervalsIcuApiKey: 'test-key',
        },
      );
      // In test env without network, this will return failure (not throw)
      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(
        result.status,
        anyOf(FitUploadPlatformStatus.failure, FitUploadPlatformStatus.success),
      );
    });
  });
}
```

- [ ] **Step 2: Implement IntervalsIcuFitUploader**

```dart
import 'dart:io';
import 'fit_upload_coordinator.dart';
import 'intervals_icu_client.dart';
import 'settings_service.dart';

class IntervalsIcuFitUploader implements FitPlatformUploader {
  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    final athleteId = settings[SettingsService.keyIntervalsIcuAthleteId] ?? '';
    final apiKey = settings[SettingsService.keyIntervalsIcuApiKey] ?? '';

    if (athleteId.isEmpty || apiKey.isEmpty) {
      return const FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: 'Intervals.icu 凭证未配置',
      );
    }

    final client = IntervalsIcuClient(athleteId: athleteId, apiKey: apiKey);
    try {
      final activityId = await client.uploadFit(file);
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: activityId > 0
            ? FitUploadPlatformStatus.success
            : FitUploadPlatformStatus.alreadyUploaded,
        remoteActivityId: activityId > 0 ? activityId : null,
      );
    } on IntervalsIcuPermanentError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    } on IntervalsIcuRetriableError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    }
  }
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test test/services/intervals_icu_fit_uploader_test.dart`

- [ ] **Step 4: Commit**

```bash
git add lib/services/intervals_icu_fit_uploader.dart test/services/intervals_icu_fit_uploader_test.dart
git commit -m "feat: add IntervalsIcuFitUploader for share-upload flow"
```

---

### Task 8: FitUploadCoordinator — Add Intervals.icu Platform

**Files:**
- Modify: `lib/services/fit_upload_coordinator.dart`
- Modify: `test/services/fit_upload_coordinator_test.dart`

- [ ] **Step 1: Add intervalsIcu to FitUploadPlatform enum**

Change line 7:
```dart
enum FitUploadPlatform { strava, xingzhe, intervalsIcu }
```

- [ ] **Step 2: Add IntervalsIcuUploader to FitUploadCoordinator**

Add constructor param and field:
```dart
FitUploadCoordinator({
  FitPlatformUploader? stravaUploader,
  FitPlatformUploader? xingzheUploader,
  FitPlatformUploader? intervalsIcuUploader,
  // ... existing params
}) : _stravaUploader = stravaUploader ?? StravaFitUploader(...),
     _xingzheUploader = xingzheUploader ?? XingzheFitUploader(...),
     _intervalsIcuUploader = intervalsIcuUploader ?? IntervalsIcuFitUploader();

final FitPlatformUploader _intervalsIcuUploader;
```

- [ ] **Step 3: Update resolveUploadPlan**

Add after Xingzhe check:
```dart
if (_isEnabled(settings, SettingsService.keyUploadToIntervalsIcu)) {
  targets.add(FitUploadPlatform.intervalsIcu);
}
```

- [ ] **Step 4: Update _uploadToPlatform switch**

Add case:
```dart
FitUploadPlatform.intervalsIcu => _intervalsIcuUploader,
```

- [ ] **Step 5: Update _hasRequiredConfiguration**

Add:
```dart
if (platform == FitUploadPlatform.intervalsIcu &&
    (!_hasValue(settings, SettingsService.keyIntervalsIcuAthleteId) ||
        !_hasValue(settings, SettingsService.keyIntervalsIcuApiKey))) {
  return false;
}
```

- [ ] **Step 6: Update _targetLabel**

Add Intervals.icu to label combinations.

- [ ] **Step 7: Run tests**

Run: `flutter test test/services/fit_upload_coordinator_test.dart`

- [ ] **Step 8: Commit**

```bash
git add lib/services/fit_upload_coordinator.dart test/services/fit_upload_coordinator_test.dart
git commit -m "feat: add Intervals.icu to FitUploadCoordinator"
```

---

### Task 9: SyncEngine — Add Intervals.icu Upload

**Files:**
- Modify: `lib/services/sync_engine.dart`
- Modify: `test/services/sync_engine_test.dart`

- [ ] **Step 1: Add import and constructor params**

Add import at top:
```dart
import 'intervals_icu_client.dart';
```

Add to constructor:
```dart
final IntervalsIcuClient? intervalsIcuClient;
final bool uploadToIntervalsIcu;
// ...
SyncEngine({
  // ... existing params
  this.intervalsIcuClient,
  this.uploadToIntervalsIcu = false,
});
```

- [ ] **Step 2: Add per-platform counters**

Add after `stravaFailures` (line 112):
```dart
int intervalsIcuSuccess = 0, intervalsIcuFailed = 0, intervalsIcuDeduped = 0;
final List<FailedActivitySummary> intervalsIcuFailures = [];
```

- [ ] **Step 3: Update SyncProgress initialization**

Add `intervalsIcuEnabled: uploadToIntervalsIcu` to the progress constructor call (line 97-101).

- [ ] **Step 4: Add dedup check for intervalsIcu**

In the dedup sections (both dedupeKey-fingerprint and fingerprint-only), add after Xingzhe dedup check:
```dart
bool skipIntervalsIcu = false;
if (uploadToIntervalsIcu) {
  final already = await stateStore.isAlreadyUploaded(storedFp, 'intervals_icu');
  if (already) {
    skipIntervalsIcu = true;
    preSkipped.add(PlatformSyncResult(
      platform: SyncPlatform.intervalsIcu,
      status: SyncStatus.deduped,
      syncedAt: DateTime.now().toIso8601String(),
    ));
  }
}
```

Update the "all platforms done" check to include intervalsIcu.

- [ ] **Step 5: Add _uploadToIntervalsIcu helper**

Create new method following `_uploadToXingzhe` pattern (but simpler — no polling):
```dart
Future<_PlatformUploadResult> _uploadToIntervalsIcu({
  required String fingerprint,
  required String sourceFilename,
  required String startTime,
  required FitSessionMeta sessionMeta,
  required File uploadFile,
  required bool rewriteFailed,
  required String? rewriteError,
  required String now,
}) async {
  final platformResults = <PlatformSyncResult>[];
  int uploaded = 0, failed = 0;
  int iSuccess = 0, iDeduped = 0;
  final List<FailedActivitySummary> iFailures = [];
  final List<String> iFailureReasons = [];

  final skip = await stateStore.isAlreadyUploaded(fingerprint, 'intervals_icu');
  if (skip) {
    platformResults.add(
      PlatformSyncResult(
        platform: SyncPlatform.intervalsIcu,
        status: SyncStatus.deduped,
        syncedAt: now,
      ),
    );
    iDeduped++;
  } else if (!gcjCorrectionEnabled || !rewriteFailed) {
    try {
      final activityId = await intervalsIcuClient!.uploadFit(uploadFile);
      await stateStore.markPlatformSynced(
        fingerprint,
        'intervals_icu',
        activityId > 0 ? activityId : null,
      );
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.intervalsIcu,
          status: SyncStatus.success,
          remoteActivityId: activityId > 0 ? activityId : null,
          syncedAt: now,
        ),
      );
      uploaded++;
      iSuccess++;
    } catch (e) {
      if (_isIdempotentSuccess(e)) {
        await stateStore.markPlatformSynced(fingerprint, 'intervals_icu', null);
        platformResults.add(
          PlatformSyncResult(
            platform: SyncPlatform.intervalsIcu,
            status: SyncStatus.success,
            syncedAt: now,
          ),
        );
        uploaded++;
        iSuccess++;
      } else {
        platformResults.add(
          PlatformSyncResult(
            platform: SyncPlatform.intervalsIcu,
            status: SyncStatus.failed,
            errorMessage: '$e',
            syncedAt: now,
          ),
        );
        failed++;
        iFailures.add(
          _failSummary(fingerprint, startTime, sessionMeta, '$e'),
        );
        iFailureReasons.add('Intervals.icu 上传失败 ($sourceFilename): $e');
      }
    }
  } else {
    platformResults.add(
      PlatformSyncResult(
        platform: SyncPlatform.intervalsIcu,
        status: SyncStatus.failed,
        errorMessage: '坐标转换失败: $rewriteError',
        syncedAt: now,
      ),
    );
    failed++;
    iFailures.add(
      _failSummary(fingerprint, startTime, sessionMeta, '坐标转换失败'),
    );
  }

  return _PlatformUploadResult(
    platformResults: platformResults,
    uploaded: uploaded,
    failed: failed,
    success: iSuccess,
    deduped: iDeduped,
    failures: iFailures,
    failureReasons: iFailureReasons,
  );
}
```

- [ ] **Step 6: Add Intervals.icu to parallel upload section**

After the Xingzhe upload future (line 422-435), add:
```dart
final List<_PlatformUploadResult> intervalsIcuResults = [];

if (uploadToIntervalsIcu && intervalsIcuClient != null) {
  uploadFutures.add(
    _uploadToIntervalsIcu(
      fingerprint: currentFingerprint,
      sourceFilename: item.sourceFilename,
      startTime: item.startTime,
      sessionMeta: sessionMeta,
      uploadFile: uploadFile,
      rewriteFailed: rewriteFailed,
      rewriteError: rewriteError,
      now: now,
    ).then((r) => intervalsIcuResults.add(r)),
  );
}
```

- [ ] **Step 7: Aggregate Intervals.icu results**

After Xingzhe aggregation (line 456-465), add:
```dart
for (final r in intervalsIcuResults) {
  platformResults.addAll(r.platformResults);
  platformsUploaded += r.uploaded;
  platformsFailed += r.failed;
  intervalsIcuSuccess += r.success;
  intervalsIcuFailed += r.failed;
  intervalsIcuDeduped += r.deduped;
  intervalsIcuFailures.addAll(r.failures);
  failureReasons.addAll(r.failureReasons);
}
```

- [ ] **Step 8: Update progress notification**

Add intervalsIcu to progress copyWith after Xingzhe (line 475-478).

- [ ] **Step 9: Update SyncSummary return**

Add intervalsIcu fields to the return statement (line 530-545).

- [ ] **Step 10: Update _failedRecord**

Add intervalsIcu to the platformResults list (line 592-608).

- [ ] **Step 11: Run tests**

Run: `flutter test test/services/sync_engine_test.dart`

- [ ] **Step 12: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "feat: add Intervals.icu upload to SyncEngine"
```

---

### Task 10: Settings Pages — Refactor + Intervals.icu

**Files:**
- Create: `lib/screens/strava_settings_screen.dart`
- Create: `lib/screens/xingzhe_settings_screen.dart`
- Create: `lib/screens/intervals_icu_settings_screen.dart`
- Modify: `lib/screens/settings_screen.dart`
- Modify: `test/screens/settings_screen_test.dart`

- [ ] **Step 1: Create StravaSettingsScreen**

Extract all Strava-related UI from `SettingsScreen` into `lib/screens/strava_settings_screen.dart`. This includes:
- Upload mode selector (API/Web)
- API mode: OAuth button, credential fields
- Web mode: Login button, status display

- [ ] **Step 2: Create XingzheSettingsScreen**

Extract all Xingzhe-related UI into `lib/screens/xingzhe_settings_screen.dart`:
- Username/password fields
- Login validation button

- [ ] **Step 3: Create IntervalsIcuSettingsScreen**

New file `lib/screens/intervals_icu_settings_screen.dart`:
- Athlete ID input (hint: "i12345")
- API Key input (obscured)
- Info text: "在 Intervals.icu 设置 > Developer 中生成 API Key"

- [ ] **Step 4: Refactor SettingsScreen**

Replace Strava/Xingzhe sections with a "同步平台" section containing three cards:
- Each card: `[平台名称] [启用开关] [chevron_right]`
- Switch toggles save `UPLOAD_TO_*` immediately (existing pattern)
- Tapping card navigates to sub-page via `Navigator.push`

- [ ] **Step 5: Update settings_screen_test.dart**

Update tests for the refactored layout.

- [ ] **Step 6: Run all screen tests**

Run: `flutter test test/screens/`

- [ ] **Step 7: Commit**

```bash
git add lib/screens/settings_screen.dart lib/screens/strava_settings_screen.dart lib/screens/xingzhe_settings_screen.dart lib/screens/intervals_icu_settings_screen.dart test/screens/settings_screen_test.dart
git commit -m "feat: refactor settings into platform sub-pages, add Intervals.icu settings"
```

---

### Task 11: HomeScreen — Intervals.icu UI

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `test/screens/home_screen_test.dart`

- [ ] **Step 1: Add Intervals.icu import and client construction**

In `_sync()`, add:
- Read `INTERVALS_ICU_ATHLETE_ID` and `INTERVALS_ICU_API_KEY` from settings
- Read `UPLOAD_TO_INTERVALS_ICU` toggle
- Validate credentials if enabled
- Create `IntervalsIcuClient` instance
- Pass to `SyncEngine` constructor

- [ ] **Step 2: Update "no platform selected" check**

Change the check from `!uploadToStrava && !uploadToXingzhe` to include `!uploadToIntervalsIcu`.

- [ ] **Step 3: Add Intervals.icu progress bar**

In `_SyncProgressDialog`, add after Xingzhe progress bar:
```dart
if (progress.intervalsIcuEnabled && progress.uploadTotal > 0) ...[
  const Text('上传至 Intervals.icu', style: TextStyle(fontSize: 13)),
  const SizedBox(height: 4),
  LinearProgressIndicator(
    value: progress.uploadTotal > 0
        ? progress.intervalsIcuUploaded / progress.uploadTotal
        : 0,
  ),
  const SizedBox(height: 2),
  Text(
    '${progress.intervalsIcuUploaded}/${progress.uploadTotal}',
    style: const TextStyle(fontSize: 12, color: Colors.grey),
  ),
],
```

- [ ] **Step 4: Add Intervals.icu to banner detail**

In `_showBannerDetail()`, add Intervals.icu section after Strava.

In `_bannerItem()`, add Intervals.icu platform chip.

- [ ] **Step 5: Update SyncProgress initialization**

Add `intervalsIcuEnabled: uploadToIntervalsIcu` to the progress notifier initial value.

- [ ] **Step 6: Run tests**

Run: `flutter test test/screens/home_screen_test.dart`

- [ ] **Step 7: Commit**

```bash
git add lib/screens/home_screen.dart test/screens/home_screen_test.dart
git commit -m "feat: add Intervals.icu UI to home screen"
```

---

### Task 12: Verification

**Files:** None (verification only)

- [ ] **Step 1: Format check**

Run: `dart format --output=none --set-exit-if-changed lib test`

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`

- [ ] **Step 3: Run all tests**

Run: `flutter test`

- [ ] **Step 4: Final commit if needed**

```bash
git add -A
git commit -m "chore: format and analyze fixes"
```
