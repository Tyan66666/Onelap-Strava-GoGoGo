import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/sync_record.dart';
import 'package:onelap_strava_sync/services/state_store.dart';

SyncRecord _failedRecord({
  required String sourceFilename,
  required String startTime,
  required DateTime syncedAt,
  required String errorMessage,
}) {
  return SyncRecord(
    fingerprint: '',
    sourceFilename: sourceFilename,
    startTime: startTime,
    syncedAt: syncedAt,
    platformResults: <PlatformSyncResult>[
      PlatformSyncResult(
        platform: SyncPlatform.strava,
        status: SyncStatus.failed,
        errorMessage: errorMessage,
        syncedAt: syncedAt.toIso8601String(),
      ),
    ],
  );
}

SyncRecord _successfulRecord({
  required String fingerprint,
  required String sourceFilename,
  required String startTime,
  required DateTime syncedAt,
}) {
  return SyncRecord(
    fingerprint: fingerprint,
    sourceFilename: sourceFilename,
    startTime: startTime,
    syncedAt: syncedAt,
    platformResults: <PlatformSyncResult>[
      PlatformSyncResult(
        platform: SyncPlatform.strava,
        status: SyncStatus.success,
        remoteActivityId: 123,
        syncedAt: syncedAt.toIso8601String(),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory documentsDirectory;

  setUp(() async {
    documentsDirectory = await Directory.systemTemp.createTemp(
      'state-store-documents-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'getApplicationDocumentsDirectory') {
            return documentsDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  group('StateStore.loadSyncRecords', () {
    test('keeps distinct failed records when fingerprint is empty', () async {
      final StateStore store = StateStore();
      final SyncRecord first = _failedRecord(
        sourceFilename: 'first.fit',
        startTime: '2026-04-10T08:00:00Z',
        syncedAt: DateTime.parse('2026-04-10T09:00:00Z'),
        errorMessage: 'download failed',
      );
      final SyncRecord second = _failedRecord(
        sourceFilename: 'second.fit',
        startTime: '2026-04-11T08:00:00Z',
        syncedAt: DateTime.parse('2026-04-11T09:00:00Z'),
        errorMessage: 'fingerprint failed',
      );

      await store.saveSyncRecords(<SyncRecord>[first, second]);

      final List<SyncRecord> loaded = await store.loadSyncRecords(limit: 10);

      expect(loaded, hasLength(2));
      expect(
        loaded.map((record) => record.sourceFilename),
        containsAll(<String>['first.fit', 'second.fit']),
      );
    });

    test(
      'merges a later fingerprinted retry with the original fallback identity',
      () async {
        final StateStore store = StateStore();
        final SyncRecord failed = _failedRecord(
          sourceFilename: 'retry.fit',
          startTime: '2026-04-12T08:00:00Z',
          syncedAt: DateTime.parse('2026-04-12T09:00:00Z'),
          errorMessage: 'download failed',
        );
        final SyncRecord succeeded = _successfulRecord(
          fingerprint: 'fp-123',
          sourceFilename: 'retry.fit',
          startTime: '2026-04-12T08:00:00Z',
          syncedAt: DateTime.parse('2026-04-12T10:00:00Z'),
        );

        await store.saveSyncRecords(<SyncRecord>[failed]);
        await store.saveSyncRecords(<SyncRecord>[succeeded]);

        final List<SyncRecord> loaded = await store.loadSyncRecords(limit: 10);

        expect(loaded, hasLength(1));
        expect(loaded.single.fingerprint, 'fp-123');
        expect(loaded.single.sourceFilename, 'retry.fit');
        expect(loaded.single.platformResults, hasLength(1));
        expect(loaded.single.platformResults.single.status, SyncStatus.success);
      },
    );

    test(
      'round-trips a shared upload record with mixed platform results',
      () async {
        final StateStore store = StateStore();
        final DateTime syncedAt = DateTime.parse('2026-04-13T10:11:12Z');
        final SyncRecord record = SyncRecord(
          fingerprint: '',
          sourceFilename: 'shared.fit',
          startTime: '2026-04-13T08:09:10Z',
          syncedAt: syncedAt,
          distanceM: 23456,
          ascentM: 456,
          sport: 'cycling',
          uploadedToStrava: true,
          uploadedToXingzhe: true,
          platformResults: <PlatformSyncResult>[
            PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.success,
              remoteActivityId: 789,
              syncedAt: syncedAt.toIso8601String(),
            ),
            PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.failed,
              errorMessage: 'session expired',
              syncedAt: syncedAt.toIso8601String(),
            ),
          ],
        );

        await store.saveSyncRecords(<SyncRecord>[record]);

        final List<SyncRecord> loaded = await store.loadSyncRecords(limit: 10);

        expect(loaded, hasLength(1));
        expect(loaded.single.sourceFilename, 'shared.fit');
        expect(loaded.single.startTime, '2026-04-13T08:09:10Z');
        expect(loaded.single.distanceM, 23456);
        expect(loaded.single.ascentM, 456);
        expect(loaded.single.sport, 'cycling');
        expect(loaded.single.uploadedToStrava, isTrue);
        expect(loaded.single.uploadedToXingzhe, isTrue);
        expect(loaded.single.platformResults, hasLength(2));
        expect(loaded.single.platformResults[0].platform, SyncPlatform.strava);
        expect(loaded.single.platformResults[0].status, SyncStatus.success);
        expect(loaded.single.platformResults[0].remoteActivityId, 789);
        expect(loaded.single.platformResults[1].platform, SyncPlatform.xingzhe);
        expect(loaded.single.platformResults[1].status, SyncStatus.failed);
        expect(
          loaded.single.platformResults[1].errorMessage,
          'session expired',
        );
      },
    );
  });
}
