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
    await file.writeAsString(
      jsonEncode({
        'synced': {
          'fp1': {
            'platforms': {'strava': 'success'},
          },
        },
        'history': <Map<String, dynamic>>[],
        'dedupeKeys': <String, dynamic>{},
      }),
    );

    // First read loads from disk
    final r1 = await store.isAlreadyUploaded('fp1', 'strava');
    expect(r1, isTrue);

    // Overwrite file with fp2 → strava success (fp1 removed).
    // If cache works, the next read should still see fp1 from cache,
    // not fp2 from the new file on disk.
    await file.writeAsString(
      jsonEncode({
        'synced': {
          'fp2': {
            'platforms': {'strava': 'success'},
          },
        },
        'history': <Map<String, dynamic>>[],
        'dedupeKeys': <String, dynamic>{},
      }),
    );

    final r2 = await store.isAlreadyUploaded('fp1', 'strava');
    expect(
      r2,
      isTrue,
      reason: 'Cache should return stale fp1 data, not fresh fp2 from disk',
    );

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
