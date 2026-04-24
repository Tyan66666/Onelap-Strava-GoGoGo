import 'sync_summary.dart';

/// 单次同步运行的完整结果摘要（用于 HomeScreen 按钮下方列表展示）
class SyncResultBanner {
  final String id; // unique id for key/dismiss
  final DateTime syncedAt;

  // 整体概览
  final int fetched;
  final int deduped;
  final int pending; // fetched - deduped
  final int success;
  final int failed;

  // 行者
  final int xingzheSuccess;
  final int xingzheFailed;
  final int xingzheDeduped;
  final List<FailedActivitySummary> xingzheFailures;

  // Strava
  final int stravaSuccess;
  final int stravaFailed;
  final int stravaDeduped;
  final List<FailedActivitySummary> stravaFailures;

  const SyncResultBanner({
    required this.id,
    required this.syncedAt,
    required this.fetched,
    required this.deduped,
    required this.pending,
    required this.success,
    required this.failed,
    required this.xingzheSuccess,
    required this.xingzheFailed,
    required this.xingzheDeduped,
    required this.xingzheFailures,
    required this.stravaSuccess,
    required this.stravaFailed,
    required this.stravaDeduped,
    required this.stravaFailures,
  });

  factory SyncResultBanner.fromSyncSummary(SyncSummary s) {
    final ts = DateTime.now();
    return SyncResultBanner(
      id: '${ts.millisecondsSinceEpoch}_${s.fetched}_${s.deduped}',
      syncedAt: s.syncedAt ?? DateTime.now(),
      fetched: s.fetched,
      deduped: s.deduped,
      pending: s.pending,
      success: s.success,
      failed: s.failed,
      xingzheSuccess: s.xingzheSuccess,
      xingzheFailed: s.xingzheFailed,
      xingzheDeduped: s.xingzheDeduped,
      xingzheFailures: s.xingzheFailures,
      stravaSuccess: s.stravaSuccess,
      stravaFailed: s.stravaFailed,
      stravaDeduped: s.stravaDeduped,
      stravaFailures: s.stravaFailures,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'syncedAt': syncedAt.toIso8601String(),
    'fetched': fetched,
    'deduped': deduped,
    'pending': pending,
    'success': success,
    'failed': failed,
    'xingzheSuccess': xingzheSuccess,
    'xingzheFailed': xingzheFailed,
    'xingzheDeduped': xingzheDeduped,
    'xingzheFailures': xingzheFailures.map((f) => f.toJson()).toList(),
    'stravaSuccess': stravaSuccess,
    'stravaFailed': stravaFailed,
    'stravaDeduped': stravaDeduped,
    'stravaFailures': stravaFailures.map((f) => f.toJson()).toList(),
  };

  factory SyncResultBanner.fromJson(Map<String, dynamic> json) {
    return SyncResultBanner(
      id: json['id'] as String,
      syncedAt: DateTime.parse(json['syncedAt'] as String),
      fetched: json['fetched'] as int? ?? 0,
      deduped: json['deduped'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
      success: json['success'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      xingzheSuccess: json['xingzheSuccess'] as int? ?? 0,
      xingzheFailed: json['xingzheFailed'] as int? ?? 0,
      xingzheDeduped: json['xingzheDeduped'] as int? ?? 0,
      xingzheFailures:
          (json['xingzheFailures'] as List?)
              ?.map(
                (e) =>
                    FailedActivitySummary.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      stravaSuccess: json['stravaSuccess'] as int? ?? 0,
      stravaFailed: json['stravaFailed'] as int? ?? 0,
      stravaDeduped: json['stravaDeduped'] as int? ?? 0,
      stravaFailures:
          (json['stravaFailures'] as List?)
              ?.map(
                (e) =>
                    FailedActivitySummary.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }

  /// 概览行文案
  String get summaryLine => '共获取$fetched条，$deduped条已通过，$pending条需同步';

  /// 简要时间标签（用于列表显示）
  String get timeLabel {
    final now = DateTime.now();
    final diff = now.difference(syncedAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${syncedAt.month}-${syncedAt.day} ${syncedAt.hour.toString().padLeft(2, '0')}:${syncedAt.minute.toString().padLeft(2, '0')}';
  }

  /// SyncSummary 重建（兼容现有 _showSyncResult dialog）
  SyncSummary toSyncSummary() => SyncSummary(
    fetched: fetched,
    deduped: deduped,
    success: success,
    failed: failed,
    failureReasons: [
      ...xingzheFailures.map((f) => '行者失败: ${f.displayText} ${f.error ?? ''}'),
      ...stravaFailures.map(
        (f) => 'Strava失败: ${f.displayText} ${f.error ?? ''}',
      ),
    ],
    xingzheSuccess: xingzheSuccess,
    xingzheFailed: xingzheFailed,
    xingzheDeduped: xingzheDeduped,
    xingzheFailures: xingzheFailures,
    stravaSuccess: stravaSuccess,
    stravaFailed: stravaFailed,
    stravaDeduped: stravaDeduped,
    stravaFailures: stravaFailures,
  );
}
