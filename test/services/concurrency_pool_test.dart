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
      expect(
        maxSeen,
        greaterThanOrEqualTo(2),
        reason: 'Must actually run tasks concurrently',
      );
      expect(
        maxSeen,
        lessThanOrEqualTo(2),
        reason: 'Must not exceed maxConcurrent limit',
      );
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
