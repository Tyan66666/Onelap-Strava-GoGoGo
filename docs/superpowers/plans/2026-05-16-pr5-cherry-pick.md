# PR #5 Cherry-Pick: Worthwhile Changes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cherry-pick the valuable, non-regressive changes from PR #5 (Tyan66666/Onelap-Strava-GoGoGo#5) into the current codebase — skipping the `onelap_client.dart` rewrite and deduped-counter removal that would regress functionality.

**Architecture:** Nine tasks with clear ordering. Tasks 1-2 are foundational (model + API parsing) and must go first. Tasks 3, 4, 7 all modify `sync_engine.dart` — execute sequentially to avoid merge conflicts. Tasks 5, 6, 8 are independent. Task 9 (Strava deletion detection) touches `strava_client.dart`, `state_store.dart`, and `sync_engine.dart` — execute last after all sync_engine changes are settled. Each task produces a self-contained commit.

**Tech Stack:** Dart/Flutter, Dio HTTP client, `fit_tool` package, flutter_test

---

## File Map

| File | Action | Tasks |
|------|--------|-------|
| `lib/models/onelap_activity.dart` | Modify | 1 |
| `lib/services/onelap_client.dart` | Modify | 2 |
| `lib/services/sync_engine.dart` | Modify | 3, 4, 7, 9 |
| `lib/models/sync_record.dart` | Modify | 6 |
| `lib/services/xingzhe_client.dart` | Modify | 5 |
| `lib/services/fit_coordinate_rewrite_service.dart` | Modify | 8 |
| `lib/services/strava_client.dart` | Modify | 9 |
| `lib/services/state_store.dart` | Modify | 9 |
| `test/services/onelap_client_test.dart` | Modify | 2 |
| `test/services/sync_engine_test.dart` | Modify | 3, 4, 7, 9 |
| `test/services/strava_client_test.dart` | Modify | 9 |
| `test/services/xingzhe_client_test.dart` | Modify | 5 |

---

## Task 1: Add `distanceKm` / `timeSeconds` to OneLapActivity

**Files:**
- Modify: `lib/models/onelap_activity.dart`
- Test: `test/services/onelap_client_test.dart` (existing model test at line 56)

- [ ] **Step 1: Write the failing test**

Add to the existing `OneLapActivity` test group in `test/services/onelap_client_test.dart` (after line 82):

```dart
test('stores distanceKm and timeSeconds when provided', () {
  const OneLapActivity activity = OneLapActivity(
    activityId: '1',
    startTime: '2026-03-29T10:00:00',
    fitUrl: 'geo/20260329/file.fit',
    recordKey: 'fileKey:geo/20260329/file.fit',
    sourceFilename: 'file.fit',
    distanceKm: 42.5,
    timeSeconds: 5400,
  );

  expect(activity.distanceKm, 42.5);
  expect(activity.timeSeconds, 5400);
});

test('distanceKm and timeSeconds default to null', () {
  const OneLapActivity activity = OneLapActivity(
    activityId: '1',
    startTime: '2026-03-29T10:00:00',
    fitUrl: 'geo/20260329/file.fit',
    recordKey: 'fileKey:geo/20260329/file.fit',
    sourceFilename: 'file.fit',
  );

  expect(activity.distanceKm, isNull);
  expect(activity.timeSeconds, isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "stores distanceKm"`
Expected: FAIL — `distanceKm` not found on `OneLapActivity`

- [ ] **Step 3: Write minimal implementation**

In `lib/models/onelap_activity.dart`, add two optional fields:

```dart
class OneLapActivity {
  final String activityId;
  final String? recordId;
  final String startTime;
  final String fitUrl;
  final String recordKey;
  final String sourceFilename;
  final String? rawFitUrl;
  final String? rawFitUrlAlt;
  final String? rawDurl;
  final String? rawFileKey;
  final double? distanceKm;
  final int? timeSeconds;

  const OneLapActivity({
    required this.activityId,
    this.recordId,
    required this.startTime,
    required this.fitUrl,
    required this.recordKey,
    required this.sourceFilename,
    this.rawFitUrl,
    this.rawFitUrlAlt,
    this.rawDurl,
    this.rawFileKey,
    this.distanceKm,
    this.timeSeconds,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "stores distanceKm"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS (new fields are nullable, no existing code breaks)

- [ ] **Step 6: Commit**

```bash
git add lib/models/onelap_activity.dart test/services/onelap_client_test.dart
git commit -m "feat: add distanceKm/timeSeconds fields to OneLapActivity"
```

---

## Task 2: Parse distance/time from API detail response

**Files:**
- Modify: `lib/services/onelap_client.dart:108-163`
- Test: `test/services/onelap_client_test.dart`

The current `listFitActivities` calls `_fetchRideRecordDetail` (line 109) and extracts `fitUrl`/`fileKey`/`durl` from the detail, but ignores `totalDistance` (meters) and `time` (seconds). The API returns these in `data.ridingRecord`.

- [ ] **Step 1: Write the failing test**

Add a new test in the `OneLapClient.listFitActivities` group in `test/services/onelap_client_test.dart`:

```dart
test('parses distanceKm and timeSeconds from detail response', () async {
  final Dio dio = Dio();
  dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
    final String url = options.uri.toString();

    if (url == 'http://example.com/api/login') {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'data': {'token': 'tok', 'refresh_token': 'ref'},
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }

    if (url == 'https://otm.onelap.cn/api/otm/ride_record/list') {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'data': {
            'list': [
              {'id': 100, 'start_riding_time': '2026-03-29T10:00:00'},
            ],
          },
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }

    if (url == 'https://otm.onelap.cn/api/otm/ride_record/analysis/100') {
      return ResponseBody.fromString(
        jsonEncode({
          'code': 200,
          'data': {
            'ridingRecord': {
              'fileKey': 'geo/20260329/ride.fit',
              'totalDistance': 42500,
              'time': 5400,
            },
          },
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }

    return ResponseBody.fromString('not found', 404);
  });

  final OneLapClient client = OneLapClient(
    baseUrl: 'http://example.com',
    username: 'unused',
    password: 'unused',
    dio: dio,
  );

  final activities = await client.listFitActivities(
    since: DateTime.utc(2026, 3, 28),
  );

  expect(activities, hasLength(1));
  expect(activities.single.distanceKm, 42.5);
  expect(activities.single.timeSeconds, 5400);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "parses distanceKm"`
Expected: FAIL — `distanceKm` is null

- [ ] **Step 3: Write minimal implementation**

In `lib/services/onelap_client.dart`, refactor `listFitActivities` to declare detail variables before the try block (lines 108-141), then use them in `result.add`.

The current code at lines 108-141 has detail fields (`detailFitUrl`, etc.) declared inside the try block but used outside it — this already works because they're reassigned to pre-declared `rawFitUrl` etc. vars. Add two new vars following the same pattern.

**Before the try block** (after line 106, before line 108), add two new local variables:

```dart
      double? detailDistanceKm;
      int? detailTimeSeconds;
```

**Inside the try block** (after line 120 `final String detailFileKey = ...`, before line 122 `if (detailFitUrl.isNotEmpty)`), add:

```dart
        final num? distRaw = detail['totalDistance'] as num?;
        final num? timeRaw = detail['time'] as num?;
        if (distRaw != null) detailDistanceKm = distRaw.toDouble() / 1000;
        if (timeRaw != null) detailTimeSeconds = timeRaw.toInt();
```

**In the `result.add(OneLapActivity(...))` call** (lines 149-163), add the new named parameters:

```dart
          distanceKm: detailDistanceKm,
          timeSeconds: detailTimeSeconds,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "parses distanceKm"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/onelap_client.dart test/services/onelap_client_test.dart
git commit -m "feat: parse distanceKm/timeSeconds from OneLap detail API"
```

---

## Task 3: Fill missing SyncRecord fields in dedupe path

**Files:**
- Modify: `lib/services/sync_engine.dart:224-232`
- Test: `test/services/sync_engine_test.dart`

**Problem:** When dedupeKey is hit and both platforms are already synced (lines 220-234), the SyncRecord is created without `distanceM`, `ascentM`, `sport`, `uploadedToStrava`, or `uploadedToXingzhe`. The main upload path (lines 412-424) correctly fills these. This is a data completeness bug.

- [ ] **Step 1: Write the failing test**

Add to `test/services/sync_engine_test.dart` in the `SyncEngine.runOnce` group:

```dart
test('dedupe-path SyncRecord includes distanceM and platform flags', () async {
  final tempDir = await Directory.systemTemp.createTemp(
    'sync-engine-dedup-record-',
  );
  final file = File('${tempDir.path}/activity.fit');
  await file.writeAsBytes(<int>[1, 2, 3]);

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final List<SyncRecord> savedRecords = [];
  final stateStore = _FakeStateStore()
    ..synced = true; // all platforms already synced
  final originalSave = stateStore.saveSyncRecords;
  // Override saveSyncRecords to capture records
  // (We need to modify _FakeStateStore — see implementation note below)

  final engine = SyncEngine(
    oneLapClient: _FakeOneLapClient(
      activities: <OneLapActivity>[_activity()],
      downloadedFile: file,
    ),
    stravaClient: _FakeStravaClient(),
    stateStore: stateStore,
  );

  final summary = await engine.runOnce();

  // The activity should be deduped
  expect(summary.deduped, greaterThanOrEqualTo(1));
  // Verify saved record has platform flags populated (see Step 3 assertions)
});
```

**Implementation note:** The current `_FakeStateStore.saveSyncRecords` is a no-op. To capture records, override it:

```dart
class _FakeStateStore extends StateStore {
  // ... existing fields ...
  List<SyncRecord> capturedRecords = [];

  @override
  Future<void> saveSyncRecords(List<SyncRecord> records) async {
    capturedRecords.addAll(records);
  }
}
```

Then the test can assert:

```dart
expect(stateStore.capturedRecords, isNotEmpty);
final dedupRecord = stateStore.capturedRecords.first;
// distanceM comes from FIT parsing — null for synthetic [1,2,3] bytes,
// but the fix ensures it's passed through (not always null).
// The deterministic check is on platform flags:
expect(dedupRecord.uploadedToStrava, isTrue);
expect(dedupRecord.uploadedToXingzhe, isFalse);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "dedupe-path SyncRecord"`
Expected: FAIL — `uploadedToStrava` is false (platform flags not set)

- [ ] **Step 3: Write minimal implementation**

In `lib/services/sync_engine.dart`, at line 224-232, change:

```dart
            syncRecords.add(
              SyncRecord(
                fingerprint: storedFp,
                sourceFilename: item.sourceFilename,
                startTime: item.startTime,
                syncedAt: DateTime.now(),
                platformResults: preSkipped,
              ),
            );
```

To:

```dart
            syncRecords.add(
              SyncRecord(
                fingerprint: storedFp,
                sourceFilename: item.sourceFilename,
                startTime: item.startTime,
                syncedAt: DateTime.now(),
                distanceM: sessionMeta.distanceM,
                ascentM: sessionMeta.ascentM,
                sport: sessionMeta.sport,
                uploadedToStrava: uploadToStrava,
                uploadedToXingzhe: uploadToXingzhe,
                platformResults: preSkipped,
              ),
            );
```

Also apply the same fix at lines 297-305 (the second dedupe path — fingerprint-based dedup when dedupeKey was NOT hit):

```dart
          syncRecords.add(
            SyncRecord(
              fingerprint: currentFingerprint,
              sourceFilename: item.sourceFilename,
              startTime: item.startTime,
              syncedAt: DateTime.now(),
              distanceM: sessionMeta.distanceM,
              ascentM: sessionMeta.ascentM,
              sport: sessionMeta.sport,
              uploadedToStrava: uploadToStrava,
              uploadedToXingzhe: uploadToXingzhe,
              platformResults: preSkipped,
            ),
          );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "dedupe-path SyncRecord"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "fix: fill distanceM/ascentM/sport/platform flags in dedupe-path SyncRecords"
```

---

## Task 4: Enhance dedupeKey with time component

**Files:**
- Modify: `lib/services/sync_engine.dart:172-174`
- Test: `test/services/sync_engine_test.dart`

**Current:** `dedupeKey = '${item.startTime}_${distM != null ? distM.round() : 'na'}'`
**Proposed:** `dedupeKey = '${item.startTime}_${distM != null ? distM.round() : 'na'}_${item.timeSeconds ?? 'na'}'`

Adding `timeSeconds` reduces collision probability for activities with identical startTime and distance but different durations (e.g., paused rides).

- [ ] **Step 1: Write the failing test**

Add to `test/services/sync_engine_test.dart`:

```dart
test('dedupeKey includes timeSeconds when available', () async {
  final tempDir = await Directory.systemTemp.createTemp(
    'sync-engine-dedupe-key-',
  );
  final file = File('${tempDir.path}/activity.fit');
  await file.writeAsBytes(<int>[1, 2, 3]);

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String? capturedDedupeKey;
  final stateStore = _FakeStateStore()
    ..markDedupeKeyOverride = (String key, String fp) {
      capturedDedupeKey = key;
    };

  final engine = SyncEngine(
    oneLapClient: _FakeOneLapClient(
      activities: <OneLapActivity>[
        OneLapActivity(
          activityId: 'activity-id',
          startTime: '2026-04-10T08:00:00Z',
          fitUrl: 'https://example.com/activity.fit',
          recordKey: 'record-key',
          sourceFilename: 'activity.fit',
          timeSeconds: 3600,
        ),
      ],
      downloadedFile: file,
    ),
    stravaClient: _FakeStravaClient(),
    stateStore: stateStore,
  );

  await engine.runOnce();

  expect(capturedDedupeKey, isNotNull);
  expect(capturedDedupeKey, contains('_3600'));
});
```

**Implementation note:** This requires adding a `markDedupeKeyOverride` callback to `_FakeStateStore`:

```dart
void Function(String key, String fp)? markDedupeKeyOverride;

@override
Future<void> markDedupeKey(String dedupeKey, String fingerprint) async {
  markDedupeKeyOverride?.call(dedupeKey, fingerprint);
}
```

The `OneLapActivity` is constructed directly with `timeSeconds` (no `copyWith` needed — Task 1 added the field).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "dedupeKey includes timeSeconds"`
Expected: FAIL — key does not contain `_3600`

- [ ] **Step 3: Write minimal implementation**

In `lib/services/sync_engine.dart`, line 173-174, change:

```dart
      final dedupeKey =
          '${item.startTime}_${distM != null ? distM.round() : 'na'}';
```

To:

```dart
      final dedupeKey =
          '${item.startTime}_${distM != null ? distM.round() : 'na'}_${item.timeSeconds ?? 'na'}';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "dedupeKey includes timeSeconds"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "feat: include timeSeconds in dedupeKey for better dedup stability"
```

---

## Task 5: Add response type validation in xingzhe upload

**Files:**
- Modify: `lib/services/xingzhe_client.dart:331`
- Test: `test/services/xingzhe_client_test.dart`

**Problem:** Line 331 does `final payload = response.data as Map<String, dynamic>` without checking the type first. If the server returns a string (e.g., HTML error page), this throws a `TypeError` instead of a meaningful error.

- [ ] **Step 1: Write the failing test**

Add to `test/services/xingzhe_client_test.dart` in the upload group:

```dart
test('throws XingzhePermanentError when response is not a Map', () async {
  final dio = Dio();
  dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
    return ResponseBody.fromString(
      '<html>Server Error</html>',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
      },
    );
  });

  final client = XingzheClient(
    username: 'user',
    password: 'pass',
    dio: dio,
  );

  final tempDir = await Directory.systemTemp.createTemp('xingzhe-type-');
  final file = File('${tempDir.path}/test.fit');
  await file.writeAsBytes(<int>[1, 2, 3]);

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  expect(
    () => client.uploadFit(file),
    throwsA(isA<XingzhePermanentError>()),
  );
});
```

(Adjust based on existing test patterns in the file — may need `_FakeHttpClientAdapter` import.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/xingzhe_client_test.dart --plain-name "throws XingzhePermanentError when response is not a Map"`
Expected: FAIL — throws `TypeError` instead of `XingzhePermanentError`

- [ ] **Step 3: Write minimal implementation**

In `lib/services/xingzhe_client.dart`, before line 331, add a type check:

```dart
        if (response.data is! Map<String, dynamic>) {
          throw XingzhePermanentError(
            _statusSummary(
              response.statusCode,
              fallback: 'xingzhe upload returned unexpected response type',
            ),
          );
        }
        final payload = response.data as Map<String, dynamic>;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/xingzhe_client_test.dart --plain-name "throws XingzhePermanentError when response is not a Map"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/xingzhe_client.dart test/services/xingzhe_client_test.dart
git commit -m "fix: validate response type before cast in xingzhe upload"
```

---

## Task 6: Add fingerprint guard to SyncRecord.mergeWith

**Files:**
- Modify: `lib/models/sync_record.dart:178`
- Create: `test/models/sync_record_test.dart`

**Problem:** `mergeWith` doesn't verify that the other record has the same fingerprint. Merging records with different fingerprints produces incorrect results.

- [ ] **Step 1: Write the failing test**

Create `test/models/sync_record_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/sync_record.dart';

void main() {
  group('SyncRecord.mergeWith', () {
    test('returns this when fingerprints differ', () {
      final a = SyncRecord(
        fingerprint: 'fp-A',
        sourceFilename: 'a.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 9, 0),
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.success,
            syncedAt: '2026-04-10T09:00:00',
          ),
        ],
      );

      final b = SyncRecord(
        fingerprint: 'fp-B',
        sourceFilename: 'b.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 10, 0),
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.success,
            syncedAt: '2026-04-10T10:00:00',
          ),
        ],
      );

      final merged = a.mergeWith(b);

      // Should NOT merge — fingerprints differ
      expect(merged.fingerprint, 'fp-A');
      expect(merged.platformResults, hasLength(1));
      expect(merged.platformResults.single.platform, SyncPlatform.strava);
    });

    test('merges normally when fingerprints match', () {
      final a = SyncRecord(
        fingerprint: 'fp-shared',
        sourceFilename: 'a.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 9, 0),
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.success,
            syncedAt: '2026-04-10T09:00:00',
          ),
        ],
      );

      final b = SyncRecord(
        fingerprint: 'fp-shared',
        sourceFilename: 'b.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 10, 0),
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.success,
            syncedAt: '2026-04-10T10:00:00',
          ),
        ],
      );

      final merged = a.mergeWith(b);

      // Same fingerprint — should merge both platform results
      expect(merged.platformResults, hasLength(2));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sync_record_test.dart --plain-name "mergeWith returns this when fingerprints differ"`
Expected: FAIL — merged record has 2 platform results

- [ ] **Step 3: Write minimal implementation**

In `lib/models/sync_record.dart`, at the start of `mergeWith` (line 178), add:

```dart
  SyncRecord mergeWith(SyncRecord other) {
    if (fingerprint.isNotEmpty &&
        other.fingerprint.isNotEmpty &&
        fingerprint != other.fingerprint) {
      return this;
    }
    // ... existing merge logic ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/sync_record_test.dart --plain-name "mergeWith returns this when fingerprints differ"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/models/sync_record.dart test/models/sync_record_test.dart
git commit -m "fix: guard mergeWith against mismatched fingerprints"
```

---

## Task 7: Clean up download directory after sync

**Files:**
- Modify: `lib/services/sync_engine.dart` (end of `runOnce`, after line 440)
- Test: `test/services/sync_engine_test.dart`

**Problem:** `downloadDir` (`fit_downloads/` in cache) accumulates FIT files across runs. It should be cleaned up after `runOnce` completes.

- [ ] **Step 1: Write the failing test**

Add to `test/services/sync_engine_test.dart`:

```dart
test('cleans up download directory after sync', () async {
  final tempDir = await Directory.systemTemp.createTemp(
    'sync-engine-download-cleanup-',
  );
  final file = File('${tempDir.path}/activity.fit');
  await file.writeAsBytes(<int>[1, 2, 3]);

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final engine = SyncEngine(
    oneLapClient: _FakeOneLapClient(
      activities: <OneLapActivity>[_activity()],
      downloadedFile: file,
    ),
    stravaClient: _FakeStravaClient(),
    stateStore: _FakeStateStore(),
  );

  await engine.runOnce();

  // The fit_downloads directory should be cleaned up
  final downloadDir = Directory('${cacheDirectory.path}/fit_downloads');
  expect(await downloadDir.exists(), isFalse);
});
```

Note: `cacheDirectory` is already set up in `setUpAll` (line 279). The mock returns it for `getApplicationCacheDirectory`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "cleans up download directory"`
Expected: FAIL — directory still exists

- [ ] **Step 3: Write minimal implementation**

In `lib/services/sync_engine.dart`, after `stateStore.saveSyncRecords(syncRecords)` (line 439-440), add:

```dart
    // Cleanup download directory
    try {
      if (downloadDir.existsSync()) {
        await downloadDir.delete(recursive: true);
      }
    } catch (_) {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "cleans up download directory"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "fix: clean up download directory after sync completes"
```

---

## Task 8: Add FIT header size validation in rewrite service

**Files:**
- Modify: `lib/services/fit_coordinate_rewrite_service.dart:53` (start of `rewrite` method)
- Test: `test/services/fit_coordinate_rewrite_service_test.dart`

**Problem:** The `rewrite` method passes the file directly to `rewriteFitCoordinatesInIsolate` without checking if the file is a valid FIT file. A lightweight header size check (12-14 bytes) can prevent unnecessary isolate spawning for obviously invalid files.

- [ ] **Step 1: Write the failing test**

Add to `test/services/fit_coordinate_rewrite_service_test.dart`:

```dart
test('throws for file smaller than FIT header minimum', () async {
  final tempDir = await Directory.systemTemp.createTemp('fit-header-');
  final tinyFile = File('${tempDir.path}/tiny.fit');
  await tinyFile.writeAsBytes(<int>[1, 2, 3]); // only 3 bytes

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final service = FitCoordinateRewriteService(
    loadCacheDirectory: () async => tempDir,
  );

  expect(
    () => service.rewrite(tinyFile),
    throwsA(isA<Exception>()),
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/fit_coordinate_rewrite_service_test.dart --plain-name "throws for file smaller than FIT header minimum"`
Expected: FAIL — no exception thrown (isolate handles it)

- [ ] **Step 3: Write minimal implementation**

In `lib/services/fit_coordinate_rewrite_service.dart`, in the `rewrite` method (line 53), add validation before the isolate call:

```dart
  Future<File> rewrite(File inputFile, {RewriteOptions? options}) async {
    // Validate FIT header size (header is 12-14 bytes)
    final fileSize = await inputFile.length();
    if (fileSize < 12) {
      throw Exception('File too small to be a valid FIT file: $fileSize bytes');
    }
    // ... existing code ...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/fit_coordinate_rewrite_service_test.dart --plain-name "throws for file smaller than FIT header minimum"`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/fit_coordinate_rewrite_service.dart test/services/fit_coordinate_rewrite_service_test.dart
git commit -m "fix: validate FIT header size before spawning rewrite isolate"
```

---

## Task 9: Verify remote activity exists before skipping (Strava deletion detection)

**Files:**
- Modify: `lib/services/strava_client.dart`
- Modify: `lib/services/state_store.dart`
- Modify: `lib/services/sync_engine.dart:187-201, 562-571`
- Test: `test/services/strava_client_test.dart`, `test/services/sync_engine_test.dart`

**Problem:** When a user deletes an activity on Strava after syncing, the app still skips it on the next sync because `isAlreadyUploaded` only checks local state — it never verifies the activity still exists on Strava. The skip happens in two places:

1. **dedupeKey path** (`sync_engine.dart:187-201`): skips download AND upload entirely
2. **upload helper** (`sync_engine.dart:562-571`): skips upload (fingerprint-based)

**Data flow:** `markPlatformSynced(fp, 'strava', activityId)` stores `synced[fp]['strava_activity_id'] = activityId` (line 136). When `activityId` is `null` (e.g., Strava "duplicate of" response without a parseable ID), verification is impossible — the activity should be re-uploaded to be safe.

- [ ] **Step 1: Add `getRemoteActivityId` to StateStore**

In `lib/services/state_store.dart`, add after `isAlreadyUploaded` (after line 110):

```dart
  /// 获取某 fingerprint 在指定平台的远端活动 ID。
  Future<int?> getRemoteActivityId(
    String fingerprint,
    String platform,
  ) async {
    final data = await _load();
    final synced = (data['synced'] as Map)[fingerprint] as Map?;
    if (synced == null) return null;
    final id = synced['${platform}_activity_id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return null;
  }

  /// 清除某 fingerprint 在指定平台的同步状态。
  /// 当远端活动被删除后调用，允许下次重新上传。
  Future<void> clearPlatformStatus(
    String fingerprint,
    String platform,
  ) async {
    final data = await _load();

    // 1. 清除 synced 指纹表
    final synced = (data['synced'] as Map)[fingerprint] as Map?;
    if (synced != null) {
      (synced['platforms'] as Map?)?.remove(platform);
      synced.remove('${platform}_activity_id');
    }

    // 2. 清除 dedupeKeys 中对应 fingerprint 的 platforms 状态
    final dedupeKeys = data['dedupeKeys'] as Map?;
    if (dedupeKeys != null) {
      for (final entry in dedupeKeys.entries) {
        final v = entry.value;
        if (v is Map && (v['fingerprint'] as String?) == fingerprint) {
          (v['platforms'] as Map?)?.remove(platform);
          break;
        }
      }
    }
    await _save(data);
  }
```

- [ ] **Step 2: Add `activityExists` to StravaClient**

In `lib/services/strava_client.dart`, add after `pollUpload` (after line 171):

```dart
  /// 检查指定活动是否仍存在于 Strava。
  /// 返回 true 表示存在，false 表示已删除（404）。
  Future<bool> activityExists(int activityId) async {
    final token = await ensureAccessToken();
    try {
      final response = await _dio.get(
        'https://www.strava.com/api/v3/activities/$activityId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode == HttpStatus.notFound) return false;
      return true;
    } on DioException catch (_) {
      // 网络错误等：假设存在（不删除本地状态）
      return true;
    }
  }
```

Note: `validateStatus` accepts 404 (doesn't throw), then we check `response.statusCode` explicitly. For network errors (DioException), returns true (fail-open — don't clear status on transient errors).

- [ ] **Step 3: Write failing test for StravaClient.activityExists**

Add to `test/services/strava_client_test.dart`:

```dart
group('StravaClient.activityExists', () {
  test('returns true when activity exists', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
      if (options.uri.toString().contains('/api/v3/activities/123')) {
        return ResponseBody.fromString(
          jsonEncode({'id': 123, 'name': 'Test'}),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      }
      return ResponseBody.fromString('not found', 404);
    });

    final client = StravaClient(
      clientId: 'id',
      clientSecret: 'secret',
      refreshToken: 'refresh',
      accessToken: 'valid-token',
      expiresAt: 4102444800,
      dio: dio,
    );

    expect(await client.activityExists(123), isTrue);
  });

  test('returns false when activity is deleted (404)', () async {
    final Dio dio = Dio();
    dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
      return ResponseBody.fromString(
        '{"errors": [{"resource": "Activity", "code": "not found"}]}',
        404,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    });

    final client = StravaClient(
      clientId: 'id',
      clientSecret: 'secret',
      refreshToken: 'refresh',
      accessToken: 'valid-token',
      expiresAt: 4102444800,
      dio: dio,
    );

    expect(await client.activityExists(999), isFalse);
  });
});
```

- [ ] **Step 4: Run StravaClient tests to verify**

Run: `flutter test test/services/strava_client_test.dart --plain-name "activityExists"`
Expected: PASS

- [ ] **Step 5: Add verification in `_uploadToStrava` helper**

In `lib/services/sync_engine.dart`, replace the skip block in `_uploadToStrava` (lines 562-571):

```dart
    final skip = await stateStore.isAlreadyUploaded(fingerprint, 'strava');
    if (skip) {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.strava,
          status: SyncStatus.deduped,
          syncedAt: now,
        ),
      );
      sDeduped++;
    } else if ...
```

With:

```dart
    final skip = await stateStore.isAlreadyUploaded(fingerprint, 'strava');
    if (skip) {
      // 远端验证：确认 Strava 上该活动仍存在
      bool verified = true;
      final remoteId = await stateStore.getRemoteActivityId(
        fingerprint,
        'strava',
      );
      if (remoteId != null && stravaClient != null) {
        verified = await stravaClient!.activityExists(remoteId);
      } else if (remoteId == null) {
        // 无远端 ID（如之前 duplicate of 响应未解析出 ID），无法验证
        verified = false;
      }
      if (verified) {
        platformResults.add(
          PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.deduped,
            syncedAt: now,
          ),
        );
        sDeduped++;
      } else {
        // 远端活动已删除，清除本地状态，重新上传
        await stateStore.clearPlatformStatus(fingerprint, 'strava');
        // fall through to upload below
      }
    }
    if (!skip || ...) {
```

**Implementation note:** The current code uses `if (skip) { ... } else if (...) { ... }`. After the verification change, when `verified = false`, we need to fall through to the upload code. The cleanest refactor:

```dart
    final alreadySynced = await stateStore.isAlreadyUploaded(fingerprint, 'strava');
    bool shouldSkip = false;

    if (alreadySynced) {
      final remoteId = await stateStore.getRemoteActivityId(fingerprint, 'strava');
      bool verified = true;
      if (remoteId != null && stravaClient != null) {
        verified = await stravaClient!.activityExists(remoteId);
      } else if (remoteId == null) {
        verified = false;
      }
      if (verified) {
        shouldSkip = true;
      } else {
        await stateStore.clearPlatformStatus(fingerprint, 'strava');
      }
    }

    if (shouldSkip) {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.strava,
          status: SyncStatus.deduped,
          syncedAt: now,
        ),
      );
      sDeduped++;
    } else if (!gcjCorrectionEnabled || !rewriteFailed) {
      // ... existing upload code ...
```

- [ ] **Step 6: Add verification in dedupeKey path**

In `lib/services/sync_engine.dart`, replace the Strava check in the dedupeKey block (lines 187-201):

```dart
          if (uploadToStrava) {
            final already = await stateStore.isAlreadyUploaded(
              storedFp,
              'strava',
            );
            if (already) {
              skipStrava = true;
              preSkipped.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.deduped,
                  syncedAt: DateTime.now().toIso8601String(),
                ),
              );
            }
          }
```

With:

```dart
          if (uploadToStrava) {
            final already = await stateStore.isAlreadyUploaded(
              storedFp,
              'strava',
            );
            if (already) {
              // 远端验证
              final remoteId = await stateStore.getRemoteActivityId(
                storedFp,
                'strava',
              );
              bool verified = true;
              if (remoteId != null && stravaClient != null) {
                verified = await stravaClient!.activityExists(remoteId);
              } else if (remoteId == null) {
                verified = false;
              }
              if (verified) {
                skipStrava = true;
                preSkipped.add(
                  PlatformSyncResult(
                    platform: SyncPlatform.strava,
                    status: SyncStatus.deduped,
                    syncedAt: DateTime.now().toIso8601String(),
                  ),
                );
              } else {
                // 远端已删除，清除状态；不设 skipStrava，后续会重新上传
                await stateStore.clearPlatformStatus(storedFp, 'strava');
              }
            }
          }
```

Note: When `verified = false` in the dedupeKey path, `skipStrava` stays `false`. The condition at line 220 `(!uploadToStrava || skipStrava)` becomes `false`, so the code falls through to download + normal upload. The file will be re-downloaded and re-uploaded on this sync run.

- [ ] **Step 7: Write failing test for deletion detection**

Add to `test/services/sync_engine_test.dart`:

```dart
test('re-uploads to Strava when remote activity was deleted', () async {
  final tempDir = await Directory.systemTemp.createTemp(
    'sync-engine-strava-deleted-',
  );
  final file = File('${tempDir.path}/activity.fit');
  await file.writeAsBytes(<int>[1, 2, 3]);

  addTearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final stateStore = _FakeStateStore()
    // Pretend this fingerprint was previously synced to Strava with activityId 42
    ..uploadedPlatforms['strava'] = true
    ..remoteActivityIds['strava'] = 42;

  final stravaClient = _FakeStravaClient()
    ..activityExistsResult = false; // Simulate deleted activity

  final engine = SyncEngine(
    oneLapClient: _FakeOneLapClient(
      activities: <OneLapActivity>[_activity()],
      downloadedFile: file,
    ),
    stravaClient: stravaClient,
    stateStore: stateStore,
  );

  final summary = await engine.runOnce();

  // Should have re-uploaded (not skipped)
  expect(summary.stravaSuccess, 1);
  expect(summary.stravaDeduped, 0);
  // Should have cleared the stale status
  expect(stateStore.clearedPlatforms, contains('strava'));
});
```

**Implementation note:** Requires adding to `_FakeStateStore`:

```dart
final Map<String, int> remoteActivityIds = {};
final List<String> clearedPlatforms = [];

@override
Future<int?> getRemoteActivityId(String fingerprint, String platform) async {
  return remoteActivityIds[platform];
}

@override
Future<void> clearPlatformStatus(String fingerprint, String platform) async {
  clearedPlatforms.add(platform);
  uploadedPlatforms.remove(platform);
}
```

And to `_FakeStravaClient`:

```dart
bool activityExistsResult = true;

@override
Future<bool> activityExists(int activityId) async => activityExistsResult;
```

- [ ] **Step 8: Run tests to verify**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "re-uploads to Strava when remote activity was deleted"`
Expected: PASS

- [ ] **Step 9: Run full test suite**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 10: Commit**

```bash
git add lib/services/strava_client.dart lib/services/state_store.dart lib/services/sync_engine.dart test/services/strava_client_test.dart test/services/sync_engine_test.dart
git commit -m "fix: verify Strava activity exists before skipping (deletion detection)"
```

---

## Verification

After all tasks are complete, run the full verification pipeline:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

All three must pass before considering the work complete.

## What NOT to Port (from PR #5 analysis)

| PR Change | Reason to Skip |
|-----------|---------------|
| `onelap_client.dart` full rewrite | Current code has superior auth refresh, multi-host fallback, FIT validation |
| Remove `_refreshToken` / `_withAuthenticatedOtmRequest` | Token refresh is essential for reliability |
| Remove per-platform `deduped` counters | Loses useful UI visibility |
| Change `lookbackDays` to record count | Breaks existing UX semantics |
| `state_store.dart` replace-then-insert | Current merge preserves cross-run platform history |
| xingzhe: remove re-login on HTTP 500 | Re-login is a valid recovery strategy |
| xingzhe: remove `_statusSummary`/`_sanitizeDetail` helpers | Current code has cleaner organization |
