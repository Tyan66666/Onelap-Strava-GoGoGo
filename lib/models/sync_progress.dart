class SyncProgress {
  final int totalActivities;
  final int processed;
  final int uploadTotal;
  final int stravaUploaded;
  final int xingzheUploaded;
  final bool stravaEnabled;
  final bool xingzheEnabled;

  const SyncProgress({
    this.totalActivities = 0,
    this.processed = 0,
    this.uploadTotal = 0,
    this.stravaUploaded = 0,
    this.xingzheUploaded = 0,
    this.stravaEnabled = false,
    this.xingzheEnabled = false,
  });

  SyncProgress copyWith({
    int? totalActivities,
    int? processed,
    int? uploadTotal,
    int? stravaUploaded,
    int? xingzheUploaded,
    bool? stravaEnabled,
    bool? xingzheEnabled,
  }) {
    return SyncProgress(
      totalActivities: totalActivities ?? this.totalActivities,
      processed: processed ?? this.processed,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      stravaUploaded: stravaUploaded ?? this.stravaUploaded,
      xingzheUploaded: xingzheUploaded ?? this.xingzheUploaded,
      stravaEnabled: stravaEnabled ?? this.stravaEnabled,
      xingzheEnabled: xingzheEnabled ?? this.xingzheEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncProgress &&
          runtimeType == other.runtimeType &&
          totalActivities == other.totalActivities &&
          processed == other.processed &&
          uploadTotal == other.uploadTotal &&
          stravaUploaded == other.stravaUploaded &&
          xingzheUploaded == other.xingzheUploaded &&
          stravaEnabled == other.stravaEnabled &&
          xingzheEnabled == other.xingzheEnabled;

  @override
  int get hashCode => Object.hash(
    totalActivities,
    processed,
    uploadTotal,
    stravaUploaded,
    xingzheUploaded,
    stravaEnabled,
    xingzheEnabled,
  );

  @override
  String toString() =>
      'SyncProgress(total: $totalActivities, processed: $processed, '
      'uploadTotal: $uploadTotal, strava: $stravaUploaded/$uploadTotal, '
      'xingzhe: $xingzheUploaded/$uploadTotal)';
}
