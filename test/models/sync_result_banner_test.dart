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
  });
}
