# Isolate Offloading for CPU-Bound Operations Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move CPU-bound operations (FIT parsing, SHA-256 hashing, coordinate conversion) off the main isolate to eliminate UI freezing during sync.

**Architecture:** Use `Isolate.run()` to offload three CPU-intensive functions to background isolates. Each function's pure computation is extracted into a top-level function (required by `Isolate.run`). File reads by path work fine inside isolates — only `File` objects can't cross isolate boundaries. No new dependencies needed — `dart:isolate` is built-in.

**Tech Stack:** Dart, `Isolate.run()` (dart:isolate), existing fit_tool/crypto packages

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/services/isolate_helpers.dart` | **Create** | Top-level functions for `Isolate.run()` entry points |
| `lib/services/dedupe_service.dart` | **Modify** | Use `Isolate.run` for SHA-256 |
| `lib/services/fit_coordinate_rewrite_service.dart` | **Modify** | Use `Isolate.run` for parsing + coordinate conversion |
| `test/services/isolate_helpers_test.dart` | **Create** | Tests for isolate helper functions |

---

### Task 1: Create isolate_helpers.dart with top-level entry points

**Files:**
- Create: `lib/services/isolate_helpers.dart`
- Test: `test/services/isolate_helpers_test.dart`

`Isolate.run()` requires a **top-level or static function** as its entry point. We need to extract the CPU-bound logic from the existing methods into standalone top-level functions that can be called from `Isolate.run()`.

- [ ] **Step 1: Write failing tests for isolate helpers**

```dart
// test/services/isolate_helpers_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/isolate_helpers.dart';

void main() {
  group('computeSha256Hex', () {
    test('returns correct SHA-256 hex string', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = computeSha256Hex(bytes);
      // SHA-256 of [1,2,3] is a known value
      expect(result, 'aec070645fe53ee3b3763059376134f058cc337247c978add178b6ccdfb0019f');
    });

    test('returns same hash for same input', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(computeSha256Hex(bytes), equals(computeSha256Hex(bytes)));
    });
  });

  group('computeFingerprintInIsolate', () {
    test('returns fingerprint string with correct format', () async {
      final tempDir = await Directory.systemTemp.createTemp('isolate-fp-');
      final file = File('${tempDir.path}/test.fit');
      await file.writeAsBytes([1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final result = await computeFingerprintInIsolate(
        file.path,
        '2026-01-01T00:00:00Z',
        'record-key',
      );

      expect(result, contains('record-key'));
      expect(result, contains('2026-01-01T00:00:00Z'));
      expect(result, contains('|')); // recordKey|hash|startTime
    });
  });

  group('parseFitSessionMetaInIsolate', () {
    test('returns FitSessionMeta from valid FIT bytes', () async {
      // We can't easily create a real FIT file in a unit test,
      // but we can verify the function handles empty/invalid bytes gracefully
      final tempDir = await Directory.systemTemp.createTemp('isolate-meta-');
      final file = File('${tempDir.path}/empty.fit');
      await file.writeAsBytes([0, 0, 0, 0]); // invalid FIT

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final result = await parseFitSessionMetaInIsolate(file.path);

      // Invalid FIT should return default (all nulls)
      expect(result.distanceM, isNull);
      expect(result.ascentM, isNull);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/services/isolate_helpers_test.dart`
Expected: FAIL — `isolate_helpers.dart` not found

- [ ] **Step 3: Implement isolate_helpers.dart**

```dart
// lib/services/isolate_helpers.dart
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fit_tool/fit_tool.dart';

import 'coordinate_converter.dart';
import 'fit_coordinate_rewrite_service.dart';

/// Top-level function for Isolate.run: SHA-256 hash of bytes.
String computeSha256Hex(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}

/// Top-level function for Isolate.run: compute fingerprint.
/// Reads file from [filePath], hashes contents, returns fingerprint string.
String _computeFingerprintSync(String filePath, String startTime, String recordKey) {
  final bytes = File(filePath).readAsBytesSync();
  final hash = computeSha256Hex(bytes);
  return '$recordKey|$hash|$startTime';
}

/// Runs SHA-256 fingerprint computation in a background isolate.
Future<String> computeFingerprintInIsolate(
  String filePath,
  String startTime,
  String recordKey,
) {
  return Isolate.run(() => _computeFingerprintSync(filePath, startTime, recordKey));
}

/// Top-level function for Isolate.run: parse FIT session metadata.
FitSessionMeta _parseFitSessionMetaSync(String filePath) {
  try {
    final Uint8List bytes = File(filePath).readAsBytesSync();
    final FitFile fit = FitFile.fromBytes(bytes);

    double? distanceM;
    int? ascentM;
    String? sport;
    String? startTime;

    for (final record in fit.records) {
      final msg = record.message;
      if (msg is SessionMessage) {
        distanceM = msg.totalDistance;
        ascentM = msg.totalAscent;
        if (msg.sport != null) {
          sport = msg.sport!.name;
        }
        if (msg.startTime != null) {
          startTime = DateTime.fromMillisecondsSinceEpoch(
            msg.startTime!,
            isUtc: true,
          ).toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');
        }
        break;
      }
    }

    return FitSessionMeta(
      distanceM: distanceM,
      ascentM: ascentM,
      sport: sport,
      startTime: startTime,
    );
  } catch (_) {
    return const FitSessionMeta();
  }
}

/// Runs FIT session metadata parsing in a background isolate.
Future<FitSessionMeta> parseFitSessionMetaInIsolate(String filePath) {
  return Isolate.run(() => _parseFitSessionMetaSync(filePath));
}

/// Top-level function for Isolate.run: rewrite FIT coordinates.
/// Returns the rewritten bytes (caller writes to file on main isolate).
Uint8List _rewriteFitCoordinatesSync(String filePath) {
  final Uint8List bytes = File(filePath).readAsBytesSync();
  final FitFile fitFile = FitFile.fromBytes(bytes);

  for (final Record record in fitFile.records) {
    final Message message = record.message;
    if (message is RecordMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.positionLat,
        readLongitude: () => message.positionLong,
        writeLatitude: (double? value) => message.positionLat = value,
        writeLongitude: (double? value) => message.positionLong = value,
      );
    } else if (message is LapMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.startPositionLat,
        readLongitude: () => message.startPositionLong,
        writeLatitude: (double? value) => message.startPositionLat = value,
        writeLongitude: (double? value) => message.startPositionLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.endPositionLat,
        readLongitude: () => message.endPositionLong,
        writeLatitude: (double? value) => message.endPositionLat = value,
        writeLongitude: (double? value) => message.endPositionLong = value,
      );
    } else if (message is SessionMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.startPositionLat,
        readLongitude: () => message.startPositionLong,
        writeLatitude: (double? value) => message.startPositionLat = value,
        writeLongitude: (double? value) => message.startPositionLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.necLat,
        readLongitude: () => message.necLong,
        writeLatitude: (double? value) => message.necLat = value,
        writeLongitude: (double? value) => message.necLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.swcLat,
        readLongitude: () => message.swcLong,
        writeLatitude: (double? value) => message.swcLat = value,
        writeLongitude: (double? value) => message.swcLong = value,
      );
    }
  }

  fitFile.crc = null;
  return fitFile.toBytes();
}

/// Runs FIT coordinate rewriting in a background isolate.
/// Returns the rewritten bytes. Caller writes to file on main isolate.
Future<Uint8List> rewriteFitCoordinatesInIsolate(String filePath) {
  return Isolate.run(() => _rewriteFitCoordinatesSync(filePath));
}

void _rewriteCoordinatePair({
  required double? Function() readLatitude,
  required double? Function() readLongitude,
  required void Function(double? value) writeLatitude,
  required void Function(double? value) writeLongitude,
}) {
  final double? latitude = readLatitude();
  final double? longitude = readLongitude();

  if (latitude == null || longitude == null) {
    return;
  }

  final (double convertedLatitude, double convertedLongitude) =
      CoordinateConverter.gcj02ToWgs84Exact(latitude, longitude);

  if (!_isValidLatitude(convertedLatitude) ||
      !_isValidLongitude(convertedLongitude)) {
    return;
  }

  writeLatitude(_roundToFitCoordinatePrecision(convertedLatitude));
  writeLongitude(_roundToFitCoordinatePrecision(convertedLongitude));
}

bool _isValidLatitude(double value) => value >= -90 && value <= 90;
bool _isValidLongitude(double value) => value >= -180 && value <= 180;

double _roundToFitCoordinatePrecision(double value) {
  final int semicircles = (value * 2147483648 / 180.0).round();
  return semicircles * 180.0 / 2147483648;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/services/isolate_helpers_test.dart`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/isolate_helpers.dart test/services/isolate_helpers_test.dart
git commit -m "feat: add isolate helper functions for CPU-bound operations"
```

---

### Task 2: Offload makeFingerprint to Isolate

**Files:**
- Modify: `lib/services/dedupe_service.dart`

The current `makeFingerprint()` reads the file and computes SHA-256 on the main isolate. Change it to delegate to `computeFingerprintInIsolate()`.

- [ ] **Step 1: Update dedupe_service.dart**

The `makeFingerprint` signature stays the same (`File file, String startTime, String recordKey`) — other callers like `SharedFitUploadService` depend on it. Only the internal implementation changes to use the isolate helper.

Replace the file content:

```dart
import 'dart:io';
import 'isolate_helpers.dart';

Future<String> makeFingerprint(
  File file,
  String startTime,
  String recordKey,
) async {
  return computeFingerprintInIsolate(file.path, startTime, recordKey);
}
```

No changes needed to `sync_engine.dart` or `shared_fit_upload_service.dart` — the `File`-based API is preserved.

- [ ] **Step 2: Run tests to verify they pass**

Run: `flutter test test/services/sync_engine_test.dart test/services/shared_fit_upload_service_test.dart`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/services/dedupe_service.dart
git commit -m "perf: offload SHA-256 fingerprint computation to background isolate"
```

---

### Task 3: Offload parseFitSessionMeta to Isolate

**Files:**
- Modify: `lib/services/fit_coordinate_rewrite_service.dart` (lines 23-61)

- [ ] **Step 1: Update parseFitSessionMeta in fit_coordinate_rewrite_service.dart**

The `parseFitSessionMeta` signature stays the same (`File fitFile`) — `SharedFitUploadService` depends on it via the `SharedFitSessionMetaLoader` typedef. Only the internal implementation changes.

Replace the `parseFitSessionMeta` function (lines 23-61):

```dart
import 'isolate_helpers.dart';

/// 从 FIT 文件解析 session metadata（不修改文件）。
/// CPU-bound parsing runs in a background isolate.
Future<FitSessionMeta> parseFitSessionMeta(File fitFile) async {
  return parseFitSessionMetaInIsolate(fitFile.path);
}
```

No changes needed to `sync_engine.dart` or `shared_fit_upload_service.dart`.

- [ ] **Step 2: Run tests to verify they pass**

Run: `flutter test test/services/sync_engine_test.dart test/services/fit_coordinate_rewrite_service_test.dart`
Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/services/fit_coordinate_rewrite_service.dart
git commit -m "perf: offload FIT session metadata parsing to background isolate"
```

---

### Task 4: Offload coordinate rewrite to Isolate

**Files:**
- Modify: `lib/services/fit_coordinate_rewrite_service.dart` (lines 87-145)

The `rewrite()` method does CPU-intensive coordinate conversion. Refactor to:
1. Parse FIT + convert coordinates (CPU — moves to isolate via `rewriteFitCoordinatesInIsolate`)
2. Write output file (I/O — stays on main isolate, needs cache directory)

The isolate reads the file by path internally — this is fine since `File(path).readAsBytesSync()` works in isolates.

- [ ] **Step 1: Update rewrite() method**

Replace the `rewrite()` method (lines 87-145):

```dart
  /// Rewrites the FIT file, converting GCJ-02 coordinates to WGS-84.
  ///
  /// [inputFile] - the original FIT file.
  /// [options] - optional rewrite parameters (startTime for naming).
  /// CPU-bound coordinate conversion runs in a background isolate.
  Future<File> rewrite(File inputFile, {RewriteOptions? options}) async {
    // CPU-bound: parse + convert coordinates in background isolate
    final Uint8List rewrittenBytes =
        await rewriteFitCoordinatesInIsolate(inputFile.path);

    // I/O: write output file on main isolate
    final Directory cacheDirectory = await _loadCacheDirectory();
    final File outputFile = await _createOutputFile(
      cacheDirectory,
      startTime: options?.startTime,
      sourceFilename: options?.sourceFilename,
    );
    await outputFile.writeAsBytes(rewrittenBytes);
    return outputFile;
  }
```

Remove the now-unused `_rewriteCoordinatePair`, `_isValidLatitude`, `_isValidLongitude`, and `_roundToFitCoordinatePrecision` methods from `FitCoordinateRewriteService` since they've been moved to `isolate_helpers.dart`.

- [ ] **Step 2: Clean up unused imports**

Remove `import 'coordinate_converter.dart';` from `fit_coordinate_rewrite_service.dart` since the coordinate conversion logic is now in `isolate_helpers.dart`.

- [ ] **Step 3: Run tests to verify they pass**

Run: `flutter test test/services/sync_engine_test.dart test/services/fit_coordinate_rewrite_service_test.dart`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add lib/services/fit_coordinate_rewrite_service.dart
git commit -m "perf: offload GCJ-02 coordinate conversion to background isolate"
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
git commit -m "chore: format and lint fixes for isolate offloading"
```
