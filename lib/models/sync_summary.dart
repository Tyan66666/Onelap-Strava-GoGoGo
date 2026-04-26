/// 单个失败活动的简要摘要（用于列表展示）
class FailedActivitySummary {
  final String fingerprint;
  final String date; // displayDate: 2026-04-22
  final String distance; // displayDistance: 32.5km
  final String ascent; // displayAscent: 186m
  final String? error; // 简短错误描述

  const FailedActivitySummary({
    required this.fingerprint,
    required this.date,
    required this.distance,
    required this.ascent,
    this.error,
  });

  /// 列表展示文本：时间-距离-爬升
  String get displayText {
    final parts = <String>[date, distance];
    if (ascent != '--') parts.add(ascent);
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'date': date,
    'distance': distance,
    'ascent': ascent,
    'error': error,
  };

  factory FailedActivitySummary.fromJson(Map<String, dynamic> json) {
    return FailedActivitySummary(
      fingerprint: json['fingerprint'] as String? ?? '',
      date: json['date'] as String? ?? '',
      distance: json['distance'] as String? ?? '--',
      ascent: json['ascent'] as String? ?? '--',
      error: json['error'] as String?,
    );
  }
}

class SyncSummary {
  final int fetched;
  final int deduped; // 本地判重跳过的（不计入成功/失败）
  final int success; // 本次实际同步成功（不含 deduped 跳过）
  final int failed; // 本次实际失败（不含 deduped 跳过）
  final String? abortedReason;
  final List<String> failureReasons;

  // === 按平台统计 ===
  final int xingzheSuccess;
  final int xingzheFailed;
  final int xingzheDeduped;
  final List<FailedActivitySummary> xingzheFailures;
  final int stravaSuccess;
  final int stravaFailed;
  final int stravaDeduped;
  final List<FailedActivitySummary> stravaFailures;

  /// 本次同步运行时间戳（用于 banner 记录）
  final DateTime? syncedAt;

  const SyncSummary({
    required this.fetched,
    required this.deduped,
    required this.success,
    required this.failed,
    this.abortedReason,
    this.failureReasons = const [],
    this.xingzheSuccess = 0,
    this.xingzheFailed = 0,
    this.xingzheDeduped = 0,
    this.xingzheFailures = const [],
    this.stravaSuccess = 0,
    this.stravaFailed = 0,
    this.stravaDeduped = 0,
    this.stravaFailures = const [],
    this.syncedAt,
  });

  /// 本次需同步的记录数（去除已去重的）
  int get pending => fetched - deduped;

  /// 本次实际处理的记录数（成功+失败，不含 deduped 跳过）
  int get newCount => success + failed;

  /// 生成用于 HomeScreen banner 显示的汇总文案
  String get bannerTitle {
    if (abortedReason == 'risk-control') return '同步中止（风控）';
    if (fetched == 0) return '本次未获取到记录';
    return '已同步$success条${failed > 0 ? '，失败$failed条' : ''}';
  }
}
