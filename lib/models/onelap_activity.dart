class OneLapActivity {
  final String activityId;
  final String? recordId;
  final String startTime;
  final String fitUrl;
  final String recordKey;
  final String sourceFilename;
  final String? rawFitUrl;
  final String? rawFitUrlAlt;
  final String? rawDurl;
  final String? rawFileKey;
  final double? distanceKm;
  final int? timeSeconds;

  const OneLapActivity({
    required this.activityId,
    this.recordId,
    required this.startTime,
    required this.fitUrl,
    required this.recordKey,
    required this.sourceFilename,
    this.rawFitUrl,
    this.rawFitUrlAlt,
    this.rawDurl,
    this.rawFileKey,
    this.distanceKm,
    this.timeSeconds,
  });
}
