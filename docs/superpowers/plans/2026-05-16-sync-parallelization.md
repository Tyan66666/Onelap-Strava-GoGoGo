# Sync Parallelization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parallelize sync operations — concurrent OneLap FIT downloads (limit 2) and parallel Strava+Xingzhe uploads for the same file — to reduce total sync time.

**Architecture:** Add a lightweight `Pool` class for concurrency-limited async work. Refactor `SyncEngine.runOnce()` to download FIT files concurrently (max 2) and upload to both platforms in parallel via `Future.wait`. Add in-memory caching to `StateStore` to eliminate redundant disk I/O.

**Tech Stack:** Dart, Flutter, `Future.wait`, no new dependencies (custom Pool implementation)

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/services/concurrency_pool.dart` | **Create** | Generic async pool with concurrency limit |
| `lib/services/state_store.dart` | **Modify** | Add in-memory cache for `state.json` |
| `lib/services/sync_engine.dart` | **Modify** | Concurrent downloads + parallel uploads |
| `test/services/concurrency_pool_test.dart` | **Create** | Tests for Pool class |
| `test/services/state_store_cache_test.dart` | **Create** | Tests for StateStore caching |
| `test/services/sync_engine_test.dart` | **Modify** | Update fakes for concurrent behavior |

---

### Task 1: Create ConcurrencyPool

**Files:**
- Create: `lib/services/concurrency_pool.dart`
- Test: `test/services/concurrency_pool_test.dart`

- [ ] **Step 1: Write failing tests for ConcurrencyPool**

```dart
// test/services/concurrency_pool_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/concurrency_pool.dart';

void main() {
  group('ConcurrencyPool', () {
    test('executes tasks and returns results in order', () async {
      final pool = ConcurrencyPool<int>(maxConcurrent: 2);
      final results = await pool.runAll([
        () async => 1,
        () async => 2,
        () async => 3,
      ]);
      expect(results, [1, 2, 3]);
    });

    test('limits concurrency to maxConcurrent', () async {
      int running = 0;
      int maxSeen = 0;
      final pool = ConcurrencyPool<int>(maxConcurrent: 2);

      Future<int> task() async {
        running++;
        if (running > maxSeen) maxSeen = running;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        running--;
        return maxSeen;
      }

      await pool.runAll([task, task, task, task]);
      expect(maxSeen, greaterThanOrEqualTo(2),
          reason: 'Must actually run tasks concurrently up to the limit');
    });

    test('propagates errors without breaking other tasks', () async {
      final pool = ConcurrencyPool<int>(maxConcurrent: 2);
      final results = await pool.runAll([
        () async => 1,
        () async => throw Exception('boom'),
        () async => 3,
      ]);
      expect(results[0], 1);
      expect(results[1], isA<Exception>());
      expect(results[2], 3);
    });

    test('empty list returns empty results', () async {
      final pool = ConcurrencyPool<int>(maxConcurrent: 2);
      final results = await pool.runAll(<Future<int> Function()>[]);
      expect(results, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/concurrency_pool_test.dart`
Expected: FAIL — `ConcurrencyPool` class not found

- [ ] **Step 3: Implement ConcurrencyPool**

```dart
// lib/services/concurrency_pool.dart
/// A pool that runs async tasks with a bounded concurrency limit.
///
/// Dart is single-threaded so the `nextIndex++` closure in `_worker` is safe —
/// no concurrent mutation can occur between the increment and the read.
class ConcurrencyPool<T> {
  final int maxConcurrent;

  ConcurrencyPool({required this.maxConcurrent});

  /// Runs all [tasks] concurrently (up to [maxConcurrent] at a time),
  /// returning results in the same order as the input tasks.
  /// Errors are captured as individual result values (not rethrown).
  Future<List<dynamic>> runAll(List<Future<T> Function()> tasks) async {
    if (tasks.isEmpty) return [];

    final results = List<dynamic>.filled(tasks.length, null);
    // nextIndex is mutated by workers but Dart is single-threaded, so
    // the closure captures a single shared int with no race condition.
    int nextIndex = 0;

    final workers = List<Future<void>>.generate(
      maxConcurrent.clamp(1, tasks.length),
      (_) => _worker(tasks, results, () => nextIndex++),
    );

    await Future.wait(workers);
    return results;
  }

  Future<void> _worker(
    List<Future<T> Function()> tasks,
    List<dynamic> results,
    int Function() nextIndex,
  ) async {
    while (true) {
      final index = nextIndex();
      if (index >= tasks.length) break;
      try {
        results[index] = await tasks[index]();
      } catch (e) {
        results[index] = e;
      }
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/concurrency_pool_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/concurrency_pool.dart test/services/concurrency_pool_test.dart
git commit -m "feat: add ConcurrencyPool for bounded async task execution"
```

---

### Task 2: Add in-memory cache to StateStore

**Files:**
- Modify: `lib/services/state_store.dart:22-55`
- Test: `test/services/state_store_cache_test.dart`

The current `StateStore._load()` reads and JSON-decodes `state.json` on **every single operation**. For 50 activities, this means ~250-400 redundant disk reads. Add an in-memory cache with a TTL so repeated reads within the same sync session hit memory instead of disk.

- [ ] **Step 1: Write failing tests for StateStore caching**

```dart
// test/services/state_store_cache_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/state_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('state-store-cache-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('repeated reads use cache instead of re-reading file', () async {
    final store = StateStore();
    final file = File('${tempDir.path}/state.json');

    // Seed the file with fp1 → strava success
    await file.writeAsString(jsonEncode({
      'synced': {'fp1': {'platforms': {'strava': 'success'}}},
      'history': <Map<String, dynamic>>[],
      'dedupeKeys': <String, dynamic>{},
    }));

    // First read loads from disk
    final r1 = await store.isAlreadyUploaded('fp1', 'strava');
    expect(r1, isTrue);

    // Overwrite file with fp2 → strava success (fp1 removed).
    // If cache works, the next read should still see fp1 from cache,
    // not fp2 from the new file on disk.
    await file.writeAsString(jsonEncode({
      'synced': {'fp2': {'platforms': {'strava': 'success'}}},
      'history': <Map<String, dynamic>>[],
      'dedupeKeys': <String, dynamic>{},
    }));

    final r2 = await store.isAlreadyUploaded('fp1', 'strava');
    expect(r2, isTrue, reason: 'Cache should return stale fp1 data, not fresh fp2 from disk');

    // fp2 should NOT be visible yet (cache still holds old data)
    final r3 = await store.isAlreadyUploaded('fp2', 'strava');
    expect(r3, isFalse, reason: 'Cache should not see fp2 until invalidated');
  });

  test('write invalidates cache so next read sees fresh data', () async {
    final store = StateStore();

    // Mark fp1 synced → writes to disk + invalidates cache
    await store.markPlatformSynced('fp1', 'strava', 123);

    // Next read should see the fresh data (fp1 synced)
    expect(await store.isAlreadyUploaded('fp1', 'strava'), isTrue);

    // Mark fp2 synced
    await store.markPlatformSynced('fp2', 'xingzhe', 456);

    // Both should be visible now
    expect(await store.isAlreadyUploaded('fp1', 'strava'), isTrue);
    expect(await store.isAlreadyUploaded('fp2', 'xingzhe'), isTrue);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/state_store_cache_test.dart`
Expected: FAIL — caching behavior not implemented (second read still hits disk)

- [ ] **Step 3: Add cache fields and invalidate on write**

Add to `StateStore` class (after line 21):

```dart
  Map<String, dynamic>? _cache;
  DateTime? _cacheTime;
  static const Duration _cacheTtl = Duration(seconds: 30);

  void invalidateCache() {
    _cache = null;
    _cacheTime = null;
  }
```

Replace `_load()` method (lines 27-50):

```dart
  Future<Map<String, dynamic>> _load() async {
    if (_cache != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheTtl) {
        return _cache!;
      }
    }

    final file = await _stateFile();
    if (!await file.exists()) {
      final empty = {
        'synced': {},
        'history': <Map<String, dynamic>>[],
        'dedupeKeys': <String, dynamic>{},
      };
      _cache = empty;
      _cacheTime = DateTime.now();
      return empty;
    }
    try {
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data.putIfAbsent('synced', () => <String, dynamic>{});
      data.putIfAbsent('history', () => <Map<String, dynamic>>[]);
      data.putIfAbsent('dedupeKeys', () => <String, dynamic>{});
      _cache = data;
      _cacheTime = DateTime.now();
      return data;
    } catch (_) {
      final fallback = {
        'synced': {},
        'history': <Map<String, dynamic>>[],
        'dedupeKeys': <String, dynamic>{},
      };
      _cache = fallback;
      _cacheTime = DateTime.now();
      return fallback;
    }
  }
```

Add `invalidateCache()` call at the start of `_save()` method (line 52):

```dart
  Future<void> _save(Map<String, dynamic> data) async {
    invalidateCache();
    final file = await _stateFile();
    await file.writeAsString(jsonEncode(data));
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/state_store_cache_test.dart`
Expected: PASS

- [ ] **Step 5: Run all existing StateStore tests**

Run: `flutter test test/services/state_store_test.dart`
Expected: PASS (no regressions)

- [ ] **Step 6: Commit**

```bash
git add lib/services/state_store.dart test/services/state_store_cache_test.dart
git commit -m "perf: add in-memory cache to StateStore to eliminate redundant disk I/O"
```

---

### Task 3: Parallel Strava + Xingzhe uploads

**Files:**
- Modify: `lib/services/sync_engine.dart:287-564`
- Modify: `test/services/sync_engine_test.dart`

Currently, for each activity, Strava upload runs first (lines 288-424), then Xingzhe upload (lines 427-564). Change to `Future.wait` so both run simultaneously. The helper methods must catch all exceptions internally so `Future.wait` never cancels the other platform's upload.

- [ ] **Step 1: Write a test verifying both uploads run in parallel**

Add to `test/services/sync_engine_test.dart`:

```dart
    test('strava and xingzhe uploads run in parallel', () async {
      final tempDir = await Directory.systemTemp.createTemp('sync-engine-parallel-');
      final file = File('${tempDir.path}/activity.fit');
      await file.writeAsBytes([1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      int concurrent = 0;
      int maxConcurrent = 0;

      final strava = _TrackingStravaClient(
        onStart: () {
          concurrent++;
          if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        },
        onDone: () => concurrent--,
      );
      final xingzhe = _TrackingXingzheClient(
        onStart: () {
          concurrent++;
          if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        },
        onDone: () => concurrent--,
      );

      // 2 activities so Future.wait can overlap uploads across the loop iteration
      final engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: [_activity(), _activity(sourceFilename: 'activity2.fit')],
          downloadedFile: file,
        ),
        stravaClient: strava,
        xingzheClient: xingzhe,
        stateStore: _FakeStateStore(),
        uploadToStrava: true,
        uploadToXingzhe: true,
      );

      await engine.runOnce();

      expect(maxConcurrent, greaterThanOrEqualTo(2),
          reason: 'Both platforms should upload simultaneously');
    });
```

Add the tracking fake classes near the other fakes:

```dart
class _TrackingStravaClient extends StravaClient {
  _TrackingStravaClient({this.onStart, this.onDone})
    : super(
        clientId: 'id',
        clientSecret: 'secret',
        refreshToken: 'refresh',
        accessToken: 'access',
        expiresAt: 4102444800,
      );

  final VoidCallback? onStart;
  final VoidCallback? onDone;

  @override
  Future<int> uploadFit(File file, {int retries = 3}) async {
    onStart?.call();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    onDone?.call();
    return 42;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId, {int maxAttempts = 10}) async {
    return <String, dynamic>{'activity_id': 99};
  }
}

class _TrackingXingzheClient extends XingzheClient {
  _TrackingXingzheClient({this.onStart, this.onDone})
    : super(username: 'user', password: 'pass');

  final VoidCallback? onStart;
  final VoidCallback? onDone;

  @override
  Future<int> uploadFit(File fitFile, {int retries = 3}) async {
    onStart?.call();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    onDone?.call();
    return 7;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId, {int maxAttempts = 10}) async {
    return <String, dynamic>{'activity_id': 456};
  }
}
```

- [ ] **Step 2: Run test to verify it passes (baseline)**

Run: `flutter test test/services/sync_engine_test.dart`
Expected: PASS — both upload calls already happen, just sequentially

- [ ] **Step 3: Refactor upload section to use Future.wait**

Replace the upload section in `sync_engine.dart` (lines 287-564) with parallel execution. The key change: instead of inline Strava upload then inline Xingzhe upload, extract each into a helper and run them with `Future.wait`. **Helpers must never let exceptions escape** — `Future.wait` would cancel the other platform's upload if an unhandled exception occurs.

Replace lines 287-564 with:

```dart
      // ---- upload to Strava + Xingzhe in parallel ----
      final List<_StravaUploadResult> stravaResults = [];
      final List<_XingzheUploadResult> xingzheResults = [];
      final List<String> uploadFailureReasons = [];

      final List<Future<void>> uploadFutures = [];

      if (uploadToStrava && stravaClient != null) {
        uploadFutures.add(_uploadToStrava(
          fingerprint: currentFingerprint,
          sourceFilename: item.sourceFilename,
          startTime: item.startTime,
          sessionMeta: sessionMeta,
          uploadFile: uploadFile,
          rewriteFailed: rewriteFailed,
          rewriteError: rewriteError,
          now: now,
        ).then((r) => stravaResults.add(r)));
      }

      if (uploadToXingzhe && xingzheClient != null) {
        uploadFutures.add(_uploadToXingzhe(
          fingerprint: currentFingerprint,
          sourceFilename: item.sourceFilename,
          startTime: item.startTime,
          sessionMeta: sessionMeta,
          uploadFile: uploadFile,
          rewriteFailed: rewriteFailed,
          rewriteError: rewriteError,
          now: now,
        ).then((r) => xingzheResults.add(r)));
      }

      // Run all platform uploads in parallel.
      // Each helper catches all exceptions internally, so Future.wait
      // never sees a rejected future — this is critical: if one helper
      // let an exception escape, Future.wait would cancel the other.
      await Future.wait(uploadFutures);

      // Aggregate Strava results
      for (final r in stravaResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        stravaSuccess += r.success;
        stravaFailed += r.failedCount;
        stravaDeduped += r.deduped;
        stravaFailures.addAll(r.failures);
        uploadFailureReasons.addAll(r.failureReasons);
      }

      // Aggregate Xingzhe results
      for (final r in xingzheResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        xingzheSuccess += r.success;
        xingzheFailed += r.failedCount;
        xingzheDeduped += r.deduped;
        xingzheFailures.addAll(r.failures);
        uploadFailureReasons.addAll(r.failureReasons);
      }

      // Propagate upload failure reasons to the outer list
      failureReasons.addAll(uploadFailureReasons);
```

- [ ] **Step 4: Add helper methods and result classes to SyncEngine**

Add the two result classes at the top of the file (after imports, before `SyncEngine`):

```dart
class _StravaUploadResult {
  final List<PlatformSyncResult> platformResults;
  final int uploaded;
  final int failed;
  final int success;
  final int failedCount;
  final int deduped;
  final List<FailedActivitySummary> failures;
  final List<String> failureReasons;

  const _StravaUploadResult({
    this.platformResults = const [],
    this.uploaded = 0,
    this.failed = 0,
    this.success = 0,
    this.failedCount = 0,
    this.deduped = 0,
    this.failures = const [],
    this.failureReasons = const [],
  });
}

class _XingzheUploadResult {
  final List<PlatformSyncResult> platformResults;
  final int uploaded;
  final int failed;
  final int success;
  final int failedCount;
  final int deduped;
  final List<FailedActivitySummary> failures;
  final List<String> failureReasons;

  const _XingzheUploadResult({
    this.platformResults = const [],
    this.uploaded = 0,
    this.failed = 0,
    this.success = 0,
    this.failedCount = 0,
    this.deduped = 0,
    this.failures = const [],
    this.failureReasons = const [],
  });
}
```

Add at the end of the `SyncEngine` class (before the closing `}`), these helper methods:

```dart
  // === Parallel upload helpers ===
  // Each helper catches ALL exceptions internally — never let an exception
  // escape, because Future.wait in the caller would cancel other uploads.

  FailedActivitySummary _failSummary(
    String fingerprint,
    String startTime,
    FitSessionMeta sm,
    String err,
  ) {
    String fmtDate(String s) => s.length >= 10 ? s.substring(0, 10) : s;
    String fmtDist(double? m) => m == null ? '--' : '${(m / 1000).toStringAsFixed(1)}km';
    String fmtAscent(int? m) => m == null ? '--' : '${m}m';
    return FailedActivitySummary(
      fingerprint: fingerprint,
      date: fmtDate(startTime),
      distance: fmtDist(sm.distanceM),
      ascent: fmtAscent(sm.ascentM),
      error: err,
    );
  }

  Future<_StravaUploadResult> _uploadToStrava({
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
    int sSuccess = 0, sFailed = 0, sDeduped = 0;
    final List<FailedActivitySummary> sFailures = [];
    final List<String> sFailureReasons = [];

    final skip = await stateStore.isAlreadyUploaded(fingerprint, 'strava');
    if (skip) {
      platformResults.add(PlatformSyncResult(
        platform: SyncPlatform.strava,
        status: SyncStatus.deduped,
        syncedAt: now,
      ));
      sDeduped++;
    } else if (!gcjCorrectionEnabled || !rewriteFailed) {
      try {
        final uploadId = await stravaClient!.uploadFit(uploadFile);
        final result = await stravaClient!.pollUpload(uploadId);
        final activityId = result['activity_id'];
        final error = result['error'];

        if (activityId == null && error != null) {
          final errorStr = '$error'.toLowerCase();
          if (errorStr.contains('duplicate of')) {
            await stateStore.markPlatformSynced(fingerprint, 'strava', null);
            platformResults.add(PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.deduped,
              syncedAt: now,
            ));
            sDeduped++;
          } else {
            platformResults.add(PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.failed,
              errorMessage: '$error',
              syncedAt: now,
            ));
            failed++;
            sFailed++;
            sFailures.add(_failSummary(fingerprint, startTime, sessionMeta, error));
            sFailureReasons.add('Strava 上传失败 ($sourceFilename): $error');
          }
        } else {
          final aid = (activityId as num).toInt();
          await stateStore.markPlatformSynced(fingerprint, 'strava', aid);
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.success,
            remoteActivityId: aid,
            syncedAt: now,
          ));
          uploaded++;
          sSuccess++;
        }
      } catch (e) {
        if (_isIdempotentSuccess(e)) {
          await stateStore.markPlatformSynced(fingerprint, 'strava', null);
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.success,
            syncedAt: now,
          ));
          uploaded++;
          sSuccess++;
        } else {
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.failed,
            errorMessage: '$e',
            syncedAt: now,
          ));
          failed++;
          sFailed++;
          sFailures.add(_failSummary(fingerprint, startTime, sessionMeta, '$e'));
          sFailureReasons.add('Strava 上传失败 ($sourceFilename): $e');
        }
      }
    } else {
      platformResults.add(PlatformSyncResult(
        platform: SyncPlatform.strava,
        status: SyncStatus.failed,
        errorMessage: '坐标转换失败: $rewriteError',
        syncedAt: now,
      ));
      failed++;
      sFailed++;
      sFailures.add(_failSummary(fingerprint, startTime, sessionMeta, '坐标转换失败'));
      sFailureReasons.add('Strava 上传失败 ($sourceFilename): 坐标转换失败');
    }

    return _StravaUploadResult(
      platformResults: platformResults,
      uploaded: uploaded,
      failed: failed,
      success: sSuccess,
      failedCount: sFailed,
      deduped: sDeduped,
      failures: sFailures,
      failureReasons: sFailureReasons,
    );
  }

  Future<_XingzheUploadResult> _uploadToXingzhe({
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
    int xSuccess = 0, xFailed = 0, xDeduped = 0;
    final List<FailedActivitySummary> xFailures = [];
    final List<String> xFailureReasons = [];

    final skip = await stateStore.isAlreadyUploaded(fingerprint, 'xingzhe');
    if (skip) {
      platformResults.add(PlatformSyncResult(
        platform: SyncPlatform.xingzhe,
        status: SyncStatus.deduped,
        syncedAt: now,
      ));
      xDeduped++;
    } else if (!gcjCorrectionEnabled || !rewriteFailed) {
      try {
        final uploadId = await xingzheClient!.uploadFit(uploadFile);
        final result = await xingzheClient!.pollUpload(uploadId);
        final activityId = result['activity_id'];
        final error = result['error'];

        if (activityId == null || (activityId is num && activityId == 0)) {
          final isIdempotent = _isIdempotentSuccess(error ?? '');
          if (error != null && !isIdempotent) {
            platformResults.add(PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.failed,
              errorMessage: '$error',
              syncedAt: now,
            ));
            failed++;
            xFailed++;
            xFailures.add(_failSummary(fingerprint, startTime, sessionMeta, error));
            xFailureReasons.add('行者 上传失败 ($sourceFilename): $error');
          } else {
            await stateStore.markPlatformSynced(fingerprint, 'xingzhe', null);
            platformResults.add(PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.success,
              syncedAt: now,
            ));
            uploaded++;
            xSuccess++;
          }
        } else {
          final aid = activityId is int ? activityId : int.tryParse('$activityId') ?? 0;
          await stateStore.markPlatformSynced(fingerprint, 'xingzhe', aid);
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.success,
            remoteActivityId: aid,
            syncedAt: now,
          ));
          uploaded++;
          xSuccess++;
        }
      } catch (e) {
        if (_isIdempotentSuccess(e)) {
          await stateStore.markPlatformSynced(fingerprint, 'xingzhe', null);
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.success,
            syncedAt: now,
          ));
          uploaded++;
          xSuccess++;
        } else {
          platformResults.add(PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.failed,
            errorMessage: '$e',
            syncedAt: now,
          ));
          failed++;
          xFailed++;
          xFailures.add(_failSummary(fingerprint, startTime, sessionMeta, '$e'));
          xFailureReasons.add('行者 上传失败 ($sourceFilename): $e');
        }
      }
    } else {
      platformResults.add(PlatformSyncResult(
        platform: SyncPlatform.xingzhe,
        status: SyncStatus.failed,
        errorMessage: '坐标转换失败: $rewriteError',
        syncedAt: now,
      ));
      failed++;
      xFailed++;
      xFailures.add(_failSummary(fingerprint, startTime, sessionMeta, '坐标转换失败'));
      xFailureReasons.add('行者 上传失败 ($sourceFilename): 坐标转换失败');
    }

    return _XingzheUploadResult(
      platformResults: platformResults,
      uploaded: uploaded,
      failed: failed,
      success: xSuccess,
      failedCount: xFailed,
      deduped: xDeduped,
      failures: xFailures,
      failureReasons: xFailureReasons,
    );
  }
```

- [ ] **Step 5: Remove dead code and run tests to verify they pass**

Remove the now-unused local `failSummary` closure (originally lines 74-87 in `runOnce()`) since `_failSummary` on `SyncEngine` replaces it. Also remove the local `fmtDate`, `fmtDist`, `fmtAscent` closures (lines 68-72) that were only used by `failSummary`.

Run: `flutter test test/services/sync_engine_test.dart`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "feat: parallelize Strava and Xingzhe uploads for same FIT file"
```

---

### Task 4: Concurrent OneLap FIT downloads

**Files:**
- Modify: `lib/services/sync_engine.dart:89-601`
- Modify: `test/services/sync_engine_test.dart`

Currently, `for (final item in activities)` downloads FIT files one by one. Refactor to download all FIT files concurrently (limit 2) upfront, then process each result sequentially for dedup check + upload.

- [ ] **Step 1: Write a test verifying concurrent downloads**

Add to `test/services/sync_engine_test.dart`:

```dart
    test('downloads FIT files concurrently (up to concurrency limit)', () async {
      final tempDir = await Directory.systemTemp.createTemp('sync-engine-concurrent-dl-');
      final file = File('${tempDir.path}/activity.fit');
      await file.writeAsBytes([1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      int concurrent = 0;
      int maxConcurrent = 0;

      final fakeClient = _CountingOneLapClient(
        activities: List.generate(4, (_) => _activity()),
        downloadedFile: file,
        onDownload: () {
          concurrent++;
          if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        },
        onDownloadDone: () => concurrent--,
      );

      final engine = SyncEngine(
        oneLapClient: fakeClient,
        stravaClient: _FakeStravaClient(),
        stateStore: _FakeStateStore(),
        downloadConcurrency: 2,
      );

      await engine.runOnce();

      expect(maxConcurrent, greaterThanOrEqualTo(2),
          reason: 'Must actually download concurrently up to the limit');
      expect(fakeClient.downloadCount, 4);
    });
```

Add the counting fake class near the other fakes:

```dart
class _CountingOneLapClient extends OneLapClient {
  _CountingOneLapClient({
    required this.activities,
    required this.downloadedFile,
    this.onDownload,
    this.onDownloadDone,
  }) : super(baseUrl: 'https://example.com', username: 'user', password: 'pass');

  final List<OneLapActivity> activities;
  final File downloadedFile;
  final VoidCallback? onDownload;
  final VoidCallback? onDownloadDone;
  int downloadCount = 0;

  @override
  Future<List<OneLapActivity>> listFitActivities({
    required DateTime since,
    int limit = 50,
  }) async => activities;

  @override
  Future<File> downloadFit(
    String url,
    String fileKey,
    Directory outDir, {
    OneLapActivity? activity,
  }) async {
    downloadCount++;
    onDownload?.call();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    onDownloadDone?.call();
    return downloadedFile;
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "downloads FIT files concurrently"`
Expected: FAIL — `downloadConcurrency` parameter not found

- [ ] **Step 3: Add downloadConcurrency parameter and refactor the main loop**

Add the `downloadConcurrency` field to `SyncEngine` (after line 22):

```dart
  final int downloadConcurrency;
```

Add to constructor (after line 32):

```dart
    this.downloadConcurrency = 2,
```

Add the import for `ConcurrencyPool` at the top of `sync_engine.dart`:

```dart
import 'concurrency_pool.dart';
```

Replace the entire `for (final item in activities)` loop (lines 89-601) with the two-phase structure below. **The processing body (dedupeKey check, fingerprint, coordinate rewrite, upload, result aggregation) is preserved in full — only the download is moved to Phase 1.**

```dart
    // === Phase 1: Download all FIT files concurrently (bounded by downloadConcurrency) ===
    final pool = ConcurrencyPool<_DownloadResult>(maxConcurrent: downloadConcurrency);
    final downloadTasks = activities.map((item) => () async {
      try {
        final file = await oneLapClient.downloadFit(
          item.fitUrl,
          item.sourceFilename,
          downloadDir,
          activity: item,
        );
        final meta = await parseFitSessionMeta(file);
        return _DownloadResult(item: item, file: file, meta: meta);
      } catch (e) {
        return _DownloadResult(item: item, error: e);
      }
    }).toList();

    final downloadResults = await pool.runAll(downloadTasks);

    // === Phase 2: Process each downloaded activity sequentially (dedup + upload) ===
    for (final dlResult in downloadResults) {
      if (dlResult is! _DownloadResult) continue;
      final item = dlResult.item;
      String? currentFingerprint;
      FitSessionMeta sessionMeta = const FitSessionMeta();
      File fitFile = File('');

      // ---- handle download errors ----
      if (dlResult.error != null) {
        failed++;
        final e = dlResult.error!;
        final isDio = e is DioException;
        final statusCode = isDio ? (e as DioException).response?.statusCode : null;
        final msg = isDio ? (e as DioException).message?.trim() ?? '' : '$e';
        failureReasons.add(
          '下载失败 (${item.sourceFilename}): ${[if (statusCode != null) 'HTTP $statusCode', if (msg.isNotEmpty) msg].join(' | ')}',
        );
        syncRecords.add(
          _failedRecord('', item, sessionMeta, 'download', '下载失败: $msg'),
        );
        continue;
      }

      fitFile = dlResult.file;
      sessionMeta = dlResult.meta;

      // ---- 2. 生成 dedupeKey（startTime + distance），检查是否命中 ----
      final distM = sessionMeta.distanceM;
      final dedupeKey =
          '${item.startTime}_${distM != null ? distM.round() : 'na'}';
      final alreadyDeduped = await stateStore.isDedupeKey(dedupeKey);

      if (alreadyDeduped) {
        // 该活动已完整同步过（dedupeKey 命中），跳过下载，用存储指纹判断 per-platform
        final storedFp = await stateStore.getDedupeKeyFingerprint(dedupeKey);
        currentFingerprint = storedFp;

        if (storedFp != null) {
          bool skipStrava = false;
          bool skipXingzhe = false;
          final List<PlatformSyncResult> preSkipped = [];

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
          if (uploadToXingzhe) {
            final already = await stateStore.isAlreadyUploaded(
              storedFp,
              'xingzhe',
            );
            if (already) {
              skipXingzhe = true;
              preSkipped.add(
                PlatformSyncResult(
                  platform: SyncPlatform.xingzhe,
                  status: SyncStatus.deduped,
                  syncedAt: DateTime.now().toIso8601String(),
                ),
              );
            }
          }

          if ((!uploadToStrava || skipStrava) &&
              (!uploadToXingzhe || skipXingzhe)) {
            // 两个平台都已在之前同步完，本次完全跳过，不计入任何计数
            deduped++;
            syncRecords.add(
              SyncRecord(
                fingerprint: storedFp,
                sourceFilename: item.sourceFilename,
                startTime: item.startTime,
                syncedAt: DateTime.now(),
                platformResults: preSkipped,
              ),
            );
            continue;
          }
        }
        // 有平台未完成，继续正常上传流程（dedupeKey 命中但部分平台之前失败）
      }

      // ---- 3. 计算指纹（dedupeKey 未命中时执行；dedupeKey 命中但部分平台未完成时也执行） ----
      if (currentFingerprint == null) {
        currentFingerprint = await _makeFingerprint(
          fitFile,
          item.startTime,
          item.recordKey,
        );
        if (currentFingerprint == null) {
          failed++;
          failureReasons.add('无法生成指纹 (${item.sourceFilename})');
          syncRecords.add(
            _failedRecord('', item, sessionMeta, 'fingerprint', '无法生成指纹'),
          );
          continue;
        }

        // ---- 4. 按平台指纹检查：是否已成功上传过？ ----
        bool skipStrava = false;
        bool skipXingzhe = false;
        final List<PlatformSyncResult> preSkipped = [];

        if (uploadToStrava) {
          final already = await stateStore.isAlreadyUploaded(
            currentFingerprint,
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
        if (uploadToXingzhe) {
          final already = await stateStore.isAlreadyUploaded(
            currentFingerprint,
            'xingzhe',
          );
          if (already) {
            skipXingzhe = true;
            preSkipped.add(
              PlatformSyncResult(
                platform: SyncPlatform.xingzhe,
                status: SyncStatus.deduped,
                syncedAt: DateTime.now().toIso8601String(),
              ),
            );
          }
        }

        // 两个平台都已在之前同步完
        if ((!uploadToStrava || skipStrava) &&
            (!uploadToXingzhe || skipXingzhe)) {
          deduped++;
          syncRecords.add(
            SyncRecord(
              fingerprint: currentFingerprint,
              sourceFilename: item.sourceFilename,
              startTime: item.startTime,
              syncedAt: DateTime.now(),
              platformResults: preSkipped,
            ),
          );
          continue;
        }
      }

      // ---- 5. 坐标转换 ----
      File uploadFile = fitFile;
      bool rewriteFailed = false;
      String? rewriteError;
      if (gcjCorrectionEnabled) {
        try {
          final svc = rewriteService ?? FitCoordinateRewriteService();
          uploadFile = await svc.rewrite(
            fitFile,
            options: RewriteOptions(
              startTime: item.startTime,
              sourceFilename: item.sourceFilename,
            ),
          );
        } catch (e) {
          rewriteFailed = true;
          rewriteError = '$e';
        }
      }

      final List<PlatformSyncResult> platformResults = [];
      int platformsUploaded = 0;
      int platformsFailed = 0;
      final now = DateTime.now().toIso8601String();

      // ---- upload to Strava + Xingzhe in parallel ----
      final List<_StravaUploadResult> stravaResults = [];
      final List<_XingzheUploadResult> xingzheResults = [];
      final List<String> uploadFailureReasons = [];

      final List<Future<void>> uploadFutures = [];

      if (uploadToStrava && stravaClient != null) {
        uploadFutures.add(_uploadToStrava(
          fingerprint: currentFingerprint,
          sourceFilename: item.sourceFilename,
          startTime: item.startTime,
          sessionMeta: sessionMeta,
          uploadFile: uploadFile,
          rewriteFailed: rewriteFailed,
          rewriteError: rewriteError,
          now: now,
        ).then((r) => stravaResults.add(r)));
      }

      if (uploadToXingzhe && xingzheClient != null) {
        uploadFutures.add(_uploadToXingzhe(
          fingerprint: currentFingerprint,
          sourceFilename: item.sourceFilename,
          startTime: item.startTime,
          sessionMeta: sessionMeta,
          uploadFile: uploadFile,
          rewriteFailed: rewriteFailed,
          rewriteError: rewriteError,
          now: now,
        ).then((r) => xingzheResults.add(r)));
      }

      await Future.wait(uploadFutures);

      for (final r in stravaResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        stravaSuccess += r.success;
        stravaFailed += r.failedCount;
        stravaDeduped += r.deduped;
        stravaFailures.addAll(r.failures);
        uploadFailureReasons.addAll(r.failureReasons);
      }

      for (final r in xingzheResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        xingzheSuccess += r.success;
        xingzheFailed += r.failedCount;
        xingzheDeduped += r.deduped;
        xingzheFailures.addAll(r.failures);
        uploadFailureReasons.addAll(r.failureReasons);
      }

      failureReasons.addAll(uploadFailureReasons);

      // ---- 6. 更新计数 ----
      if (platformsUploaded > 0) {
        success++;
        // 成功后保存 dedupeKey（稳定 key，兜底后续指纹变化情况）
        await stateStore.markDedupeKey(dedupeKey, currentFingerprint);
      }
      if (platformsFailed > 0 && platformsUploaded == 0) {
        failed++;
      }

      // ---- 7. 保存记录 ----
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
          platformResults: platformResults,
        ),
      );

      // Cleanup rewritten temp file
      if (uploadFile.path != fitFile.path) {
        try {
          await uploadFile.delete();
        } catch (_) {}
        try {
          await uploadFile.parent.delete();
        } catch (_) {}
      }
    }
```

Add the `_DownloadResult` class near the other result classes:

```dart
class _DownloadResult {
  final OneLapActivity item;
  final File file;
  final FitSessionMeta meta;
  final Object? error;

  _DownloadResult({
    required this.item,
    this.file = const File(''),
    this.meta = const FitSessionMeta(),
    this.error,
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/sync_engine_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Run full verification**

Run:
```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_test.dart
git commit -m "feat: concurrent OneLap FIT downloads with configurable concurrency limit"
```

---

### Task 5: Integration verification

**Files:** None (verification only)

- [ ] **Step 1: Run full verification pipeline**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```
Expected: All PASS

- [ ] **Step 2: Build APK to verify no compilation issues**

```bash
flutter build apk --debug
```
Expected: Build succeeds

- [ ] **Step 3: Final commit (if any formatting fixes needed)**

```bash
git add -A
git commit -m "chore: format and lint fixes for sync parallelization"
```
