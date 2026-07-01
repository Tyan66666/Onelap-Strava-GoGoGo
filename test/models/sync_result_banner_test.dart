import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/sync_result_banner.dart';
import 'package:onelap_strava_sync/models/sync_summary.dart';

void main() {
  group('SyncResultBanner', () {
    test('preserves per-platform deduped counts from summary', () {
      final SyncSummary summary = SyncSummary(
        fetched: 1,
        deduped: 0,
        success: 0,
        failed: 1,
        stravaSuccess: 0,
        stravaFailed: 0,
        stravaDeduped: 1,
        xingzheSuccess: 0,
        xingzheFailed: 1,
        xingzheDeduped: 0,
      );

      final SyncResultBanner banner = SyncResultBanner.fromSyncSummary(summary);
      final SyncResultBanner restored = SyncResultBanner.fromJson(
        banner.toJson(),
      );

      expect(restored.stravaDeduped, 1);
      expect(restored.xingzheDeduped, 0);
      expect(restored.stravaFailed, 0);
      expect(restored.xingzheFailed, 1);
    });

    test('keeps a platform visible when it only has deduped results', () {
      final SyncSummary summary = SyncSummary(
        fetched: 1,
        deduped: 0,
        success: 0,
        failed: 1,
        stravaDeduped: 1,
        xingzheFailed: 1,
      );

      final SyncResultBanner banner = SyncResultBanner.fromSyncSummary(summary);

      expect(
        banner.stravaSuccess > 0 ||
            banner.stravaFailed > 0 ||
            banner.stravaDeduped > 0,
        isTrue,
      );
    });

    test('intervalsIcu fields survive round-trip', () {
      final SyncSummary summary = SyncSummary(
        fetched: 2,
        deduped: 0,
        success: 1,
        failed: 1,
        stravaSuccess: 1,
        stravaFailed: 0,
        stravaDeduped: 0,
        stravaFailures: [],
        xingzheSuccess: 0,
        xingzheFailed: 1,
        xingzheDeduped: 0,
        xingzheFailures: [
          FailedActivitySummary(
            fingerprint: 'fp-1',
            date: '2026-04-20',
            distance: '10.0km',
            ascent: '100m',
            error: 'timeout',
          ),
        ],
        intervalsIcuSuccess: 2,
        intervalsIcuFailed: 0,
        intervalsIcuDeduped: 1,
        intervalsIcuFailures: [
          FailedActivitySummary(
            fingerprint: 'fp-2',
            date: '2026-04-21',
            distance: '20.0km',
            ascent: '200m',
          ),
        ],
      );

      final SyncResultBanner banner = SyncResultBanner.fromSyncSummary(summary);
      final SyncResultBanner restored = SyncResultBanner.fromJson(
        banner.toJson(),
      );

      expect(restored.intervalsIcuSuccess, 2);
      expect(restored.intervalsIcuFailed, 0);
      expect(restored.intervalsIcuDeduped, 1);
      expect(restored.intervalsIcuFailures, hasLength(1));
      expect(restored.intervalsIcuFailures.first.fingerprint, 'fp-2');
      expect(restored.intervalsIcuFailures.first.distance, '20.0km');
    });

    test('toSyncSummary preserves intervalsIcu fields', () {
      final SyncSummary original = SyncSummary(
        fetched: 3,
        deduped: 1,
        success: 1,
        failed: 1,
        intervalsIcuSuccess: 1,
        intervalsIcuFailed: 1,
        intervalsIcuDeduped: 0,
        intervalsIcuFailures: [
          FailedActivitySummary(
            fingerprint: 'fp-3',
            date: '2026-04-22',
            distance: '30.0km',
            ascent: '300m',
            error: 'API Key 无效',
          ),
        ],
      );

      final SyncResultBanner banner = SyncResultBanner.fromSyncSummary(
        original,
      );
      final SyncSummary restored = banner.toSyncSummary();

      expect(restored.intervalsIcuSuccess, 1);
      expect(restored.intervalsIcuFailed, 1);
      expect(restored.intervalsIcuDeduped, 0);
      expect(restored.intervalsIcuFailures, hasLength(1));
      expect(restored.intervalsIcuFailures.first.error, 'API Key 无效');
    });
  });
}
