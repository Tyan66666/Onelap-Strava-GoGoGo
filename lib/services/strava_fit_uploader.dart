import 'dart:io';

import 'fit_upload_coordinator.dart';
import 'settings_service.dart';
import 'strava_client.dart';

abstract class StravaFitUploadClient {
  Future<int> uploadFit(File file);

  Future<Map<String, dynamic>> pollUpload(int uploadId);
}

typedef StravaFitUploadClientFactory =
    StravaFitUploadClient Function(Map<String, String> settings);

class StravaFitUploader implements FitPlatformUploader {
  StravaFitUploader({StravaFitUploadClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final StravaFitUploadClientFactory _clientFactory;

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    final StravaFitUploadClient client = _clientFactory(settings);
    final int uploadId = await client.uploadFit(file);
    final Map<String, dynamic> pollResult = await client.pollUpload(uploadId);
    final Object? activityId = pollResult['activity_id'];
    final String message =
        '${pollResult['error'] ?? pollResult['status'] ?? ''}';

    if (activityId != null) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.strava,
        status: FitUploadPlatformStatus.success,
        remoteActivityId: _parseActivityId(activityId),
      );
    }

    if (_isDuplicateMessage(message)) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.strava,
        status: FitUploadPlatformStatus.alreadyUploaded,
        message: message,
      );
    }

    return FitUploadPlatformResult(
      platform: FitUploadPlatform.strava,
      status: FitUploadPlatformStatus.failure,
      message: 'Strava upload incomplete: $message',
    );
  }

  static StravaFitUploadClient _defaultClientFactory(
    Map<String, String> settings,
  ) {
    return _StravaFitUploadClientAdapter(
      StravaClient(
        clientId: settings[SettingsService.keyStravaClientId] ?? '',
        clientSecret: settings[SettingsService.keyStravaClientSecret] ?? '',
        refreshToken: settings[SettingsService.keyStravaRefreshToken] ?? '',
        accessToken: settings[SettingsService.keyStravaAccessToken] ?? '',
        expiresAt:
            int.tryParse(settings[SettingsService.keyStravaExpiresAt] ?? '') ??
            0,
      ),
    );
  }

  static bool _isDuplicateMessage(String message) {
    final String normalized = message.toLowerCase();
    return normalized.contains('duplicate of') ||
        normalized.contains('duplicate') ||
        normalized.contains('already exists') ||
        normalized.contains('already uploaded');
  }

  static int? _parseActivityId(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse('$value');
  }
}

class _StravaFitUploadClientAdapter implements StravaFitUploadClient {
  _StravaFitUploadClientAdapter(this._client);

  final StravaClient _client;

  @override
  Future<int> uploadFit(File file) {
    return _client.uploadFit(file);
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _client.pollUpload(uploadId);
  }
}
