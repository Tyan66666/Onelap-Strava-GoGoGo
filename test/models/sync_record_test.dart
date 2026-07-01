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

      expect(merged.platformResults, hasLength(2));
    });

    test('mergeWith merges intervalsIcu platform results', () {
      final a = SyncRecord(
        fingerprint: 'fp-shared',
        sourceFilename: 'a.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 9, 0),
        uploadedToStrava: true,
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
        uploadedToIntervalsIcu: true,
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.intervalsIcu,
            status: SyncStatus.success,
            remoteActivityId: 456,
            syncedAt: '2026-04-10T10:00:00',
          ),
        ],
      );

      final merged = a.mergeWith(b);

      expect(merged.platformResults, hasLength(2));
      expect(merged.uploadedToStrava, isTrue);
      expect(merged.uploadedToIntervalsIcu, isTrue);
      final intervalsResult = merged.platformResults.firstWhere(
        (r) => r.platform == SyncPlatform.intervalsIcu,
      );
      expect(intervalsResult.remoteActivityId, 456);
    });
  });

  group('SyncRecord intervalsIcu round-trip', () {
    test('serializes and deserializes with uploadedToIntervalsIcu', () {
      final record = SyncRecord(
        fingerprint: 'fp-test',
        sourceFilename: 'test.fit',
        startTime: '2026-04-10T08:00:00',
        syncedAt: DateTime(2026, 4, 10, 9, 0),
        uploadedToStrava: true,
        uploadedToXingzhe: false,
        uploadedToIntervalsIcu: true,
        platformResults: [
          PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.success,
            syncedAt: '2026-04-10T09:00:00',
          ),
          PlatformSyncResult(
            platform: SyncPlatform.intervalsIcu,
            status: SyncStatus.success,
            remoteActivityId: 789,
            syncedAt: '2026-04-10T09:00:00',
          ),
        ],
      );

      final json = record.toJson();
      final restored = SyncRecord.fromJson(json);

      expect(restored.fingerprint, 'fp-test');
      expect(restored.uploadedToStrava, isTrue);
      expect(restored.uploadedToXingzhe, isFalse);
      expect(restored.uploadedToIntervalsIcu, isTrue);
      expect(restored.platformResults, hasLength(2));
      final intervalsResult = restored.platformResults.firstWhere(
        (r) => r.platform == SyncPlatform.intervalsIcu,
      );
      expect(intervalsResult.status, SyncStatus.success);
      expect(intervalsResult.remoteActivityId, 789);
    });
  });
}
