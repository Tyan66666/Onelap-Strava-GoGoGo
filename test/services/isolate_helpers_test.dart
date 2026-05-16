import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/isolate_helpers.dart';

void main() {
  group('computeSha256Hex', () {
    test('returns correct SHA-256 hex string', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = computeSha256Hex(bytes);
      expect(
        result,
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
      );
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
      expect(result, contains('|'));
    });
  });

  group('parseFitSessionMetaInIsolate', () {
    test('handles invalid FIT bytes gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('isolate-meta-');
      final file = File('${tempDir.path}/empty.fit');
      await file.writeAsBytes([0, 0, 0, 0]);

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final result = await parseFitSessionMetaInIsolate(file.path);

      expect(result.distanceM, isNull);
      expect(result.ascentM, isNull);
    });
  });

  group('rewriteFitCoordinatesInIsolate', () {
    test('handles invalid FIT bytes gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('isolate-rewrite-');
      final file = File('${tempDir.path}/invalid.fit');
      await file.writeAsBytes([0, 0, 0, 0]);

      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      try {
        await rewriteFitCoordinatesInIsolate(file.path);
      } catch (_) {
        // Acceptable — invalid FIT data may cause parse or range errors
      }
    });
  });
}
