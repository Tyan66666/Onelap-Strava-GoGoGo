class SyncProgress {
  final int totalActivities;
  final int processed;
  final int uploadTotal;
  final int stravaUploaded;
  final int xingzheUploaded;
  final bool stravaEnabled;
  final bool xingzheEnabled;
  final int intervalsIcuUploaded;
  final bool intervalsIcuEnabled;
  final int outbaseUploaded;
  final bool outbaseEnabled;

  const SyncProgress({
    this.totalActivities = 0,
    this.processed = 0,
    this.uploadTotal = 0,
    this.stravaUploaded = 0,
    this.xingzheUploaded = 0,
    this.stravaEnabled = false,
    this.xingzheEnabled = false,
    this.intervalsIcuUploaded = 0,
    this.intervalsIcuEnabled = false,
    this.outbaseUploaded = 0,
    this.outbaseEnabled = false,
  });

  SyncProgress copyWith({
    int? totalActivities,
    int? processed,
    int? uploadTotal,
    int? stravaUploaded,
    int? xingzheUploaded,
    bool? stravaEnabled,
    bool? xingzheEnabled,
    int? intervalsIcuUploaded,
    bool? intervalsIcuEnabled,
    int? outbaseUploaded,
    bool? outbaseEnabled,
  }) {
    return SyncProgress(
      totalActivities: totalActivities ?? this.totalActivities,
      processed: processed ?? this.processed,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      stravaUploaded: stravaUploaded ?? this.stravaUploaded,
      xingzheUploaded: xingzheUploaded ?? this.xingzheUploaded,
      stravaEnabled: stravaEnabled ?? this.stravaEnabled,
      xingzheEnabled: xingzheEnabled ?? this.xingzheEnabled,
      intervalsIcuUploaded: intervalsIcuUploaded ?? this.intervalsIcuUploaded,
      intervalsIcuEnabled: intervalsIcuEnabled ?? this.intervalsIcuEnabled,
      outbaseUploaded: outbaseUploaded ?? this.outbaseUploaded,
      outbaseEnabled: outbaseEnabled ?? this.outbaseEnabled,
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
          xingzheEnabled == other.xingzheEnabled &&
          intervalsIcuUploaded == other.intervalsIcuUploaded &&
          intervalsIcuEnabled == other.intervalsIcuEnabled &&
          outbaseUploaded == other.outbaseUploaded &&
          outbaseEnabled == other.outbaseEnabled;

  @override
  int get hashCode => Object.hash(
    totalActivities,
    processed,
    uploadTotal,
    stravaUploaded,
    xingzheUploaded,
    stravaEnabled,
    xingzheEnabled,
    intervalsIcuUploaded,
    intervalsIcuEnabled,
    outbaseUploaded,
    outbaseEnabled,
  );

  @override
  String toString() =>
      'SyncProgress(total: $totalActivities, processed: $processed, '
      'uploadTotal: $uploadTotal, strava: $stravaUploaded/$uploadTotal, '
      'xingzhe: $xingzheUploaded/$uploadTotal, '
      'intervalsIcu: $intervalsIcuUploaded/$uploadTotal, '
      'outbase: $outbaseUploaded/$uploadTotal)';
}
