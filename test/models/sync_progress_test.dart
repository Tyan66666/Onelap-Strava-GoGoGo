import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/sync_progress.dart';

void main() {
  group('SyncProgress', () {
    test('default constructor has zero values', () {
      const p = SyncProgress();
      expect(p.totalActivities, 0);
      expect(p.processed, 0);
      expect(p.uploadTotal, 0);
      expect(p.stravaUploaded, 0);
      expect(p.xingzheUploaded, 0);
      expect(p.stravaEnabled, false);
      expect(p.xingzheEnabled, false);
      expect(p.intervalsIcuUploaded, 0);
      expect(p.intervalsIcuEnabled, false);
    });

    test('copyWith returns new instance with updated fields', () {
      const p = SyncProgress();
      final p2 = p.copyWith(
        totalActivities: 10,
        processed: 5,
        stravaEnabled: true,
        intervalsIcuEnabled: true,
        intervalsIcuUploaded: 3,
      );
      expect(p2.totalActivities, 10);
      expect(p2.processed, 5);
      expect(p2.stravaEnabled, true);
      expect(p2.uploadTotal, 0);
      expect(p2.intervalsIcuEnabled, true);
      expect(p2.intervalsIcuUploaded, 3);
    });

    test('copyWith with no arguments returns identical values', () {
      const p = SyncProgress(
        totalActivities: 3,
        processed: 2,
        uploadTotal: 1,
        stravaUploaded: 1,
        xingzheUploaded: 0,
        stravaEnabled: true,
        xingzheEnabled: true,
        intervalsIcuUploaded: 1,
        intervalsIcuEnabled: true,
      );
      final p2 = p.copyWith();
      expect(p2.totalActivities, 3);
      expect(p2.processed, 2);
      expect(p2.uploadTotal, 1);
      expect(p2.stravaUploaded, 1);
      expect(p2.xingzheUploaded, 0);
      expect(p2.stravaEnabled, true);
      expect(p2.xingzheEnabled, true);
      expect(p2.intervalsIcuUploaded, 1);
      expect(p2.intervalsIcuEnabled, true);
    });

    test('equality works correctly', () {
      const p1 = SyncProgress(
        totalActivities: 5,
        processed: 3,
        intervalsIcuUploaded: 1,
        intervalsIcuEnabled: true,
      );
      const p2 = SyncProgress(
        totalActivities: 5,
        processed: 3,
        intervalsIcuUploaded: 1,
        intervalsIcuEnabled: true,
      );
      const p3 = SyncProgress(
        totalActivities: 5,
        processed: 3,
        intervalsIcuUploaded: 2,
        intervalsIcuEnabled: true,
      );
      expect(p1, equals(p2));
      expect(p1, isNot(equals(p3)));
    });

    test('hashCode is consistent with equality', () {
      const p1 = SyncProgress(
        totalActivities: 5,
        processed: 3,
        intervalsIcuUploaded: 1,
        intervalsIcuEnabled: true,
      );
      const p2 = SyncProgress(
        totalActivities: 5,
        processed: 3,
        intervalsIcuUploaded: 1,
        intervalsIcuEnabled: true,
      );
      expect(p1.hashCode, equals(p2.hashCode));
    });
  });
}
