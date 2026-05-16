/// A pool that runs async tasks with a bounded concurrency limit.
///
/// Dart is single-threaded so the `nextIndex++` closure in `_worker` is safe —
/// no concurrent mutation can occur between the increment and the read.
class ConcurrencyPool<T> {
  final int maxConcurrent;

  ConcurrencyPool({required this.maxConcurrent});

  /// Runs all [tasks] concurrently (up to [maxConcurrent] at a time),
  /// returning results in the same order as the input tasks.
  /// Errors are captured as individual result values (not rethrown).
  Future<List<dynamic>> runAll(List<Future<T> Function()> tasks) async {
    if (tasks.isEmpty) return [];

    final results = List<dynamic>.filled(tasks.length, null);
    int nextIndex = 0;

    final workers = List<Future<void>>.generate(
      maxConcurrent.clamp(1, tasks.length),
      (_) => _worker(tasks, results, () => nextIndex++),
    );

    await Future.wait(workers);
    return results;
  }

  Future<void> _worker(
    List<Future<T> Function()> tasks,
    List<dynamic> results,
    int Function() nextIndex,
  ) async {
    while (true) {
      final index = nextIndex();
      if (index >= tasks.length) break;
      try {
        results[index] = await tasks[index]();
      } catch (e) {
        results[index] = e;
      }
    }
  }
}
