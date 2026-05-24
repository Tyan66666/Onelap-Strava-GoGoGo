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
  });
}
