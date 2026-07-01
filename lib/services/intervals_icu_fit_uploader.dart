import 'dart:io';

import 'fit_upload_coordinator.dart';
import 'intervals_icu_client.dart';
import 'settings_service.dart';

class IntervalsIcuFitUploader implements FitPlatformUploader {
  IntervalsIcuFitUploader({IntervalsIcuClient? client}) : _client = client;

  final IntervalsIcuClient? _client;

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    final athleteId = settings[SettingsService.keyIntervalsIcuAthleteId] ?? '';
    final apiKey = settings[SettingsService.keyIntervalsIcuApiKey] ?? '';

    if (athleteId.isEmpty || apiKey.isEmpty) {
      return const FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: 'Intervals.icu 凭证未配置',
      );
    }

    final client =
        _client ?? IntervalsIcuClient(athleteId: athleteId, apiKey: apiKey);
    try {
      final activityId = await client.uploadFit(file);
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: activityId > 0
            ? FitUploadPlatformStatus.success
            : FitUploadPlatformStatus.alreadyUploaded,
        remoteActivityId: activityId > 0 ? activityId : null,
      );
    } on IntervalsIcuPermanentError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    } on IntervalsIcuRetriableError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.intervalsIcu,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    }
  }
}
