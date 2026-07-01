import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/intervals_icu_client.dart';
import 'package:onelap_strava_sync/services/intervals_icu_fit_uploader.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class _FakeIntervalsIcuClient extends IntervalsIcuClient {
  _FakeIntervalsIcuClient({required this.activityId, this.error})
    : super(athleteId: '12345', apiKey: 'test-api-key');

  final int activityId;
  final Exception? error;

  @override
  Future<int> uploadFit(File file, {int retries = 3}) async {
    if (error != null) throw error!;
    return activityId;
  }
}

Map<String, String> _settings({
  String athleteId = '12345',
  String apiKey = 'test-api-key',
}) {
  return <String, String>{
    SettingsService.keyIntervalsIcuAthleteId: athleteId,
    SettingsService.keyIntervalsIcuApiKey: apiKey,
  };
}

void main() {
  group('IntervalsIcuFitUploader', () {
    late File testFile;

    setUp(() {
      testFile = File('${Directory.systemTemp.path}/intervals_icu_test.fit');
      testFile.writeAsBytesSync([0x01, 0x02, 0x03]);
    });

    tearDown(() {
      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
    });

    test('returns failure when athleteId is missing', () async {
      final uploader = IntervalsIcuFitUploader();

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(athleteId: ''),
      );

      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'Intervals.icu 凭证未配置');
    });

    test('returns failure when apiKey is missing', () async {
      final uploader = IntervalsIcuFitUploader();

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(apiKey: ''),
      );

      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'Intervals.icu 凭证未配置');
    });

    test('returns failure when both credentials are missing', () async {
      final uploader = IntervalsIcuFitUploader();

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(athleteId: '', apiKey: ''),
      );

      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'Intervals.icu 凭证未配置');
    });

    test(
      'returns failure on network error when credentials are present',
      () async {
        final uploader = IntervalsIcuFitUploader();

        final result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.platform, FitUploadPlatform.intervalsIcu);
        expect(result.status, FitUploadPlatformStatus.failure);
        expect(result.message, isNotNull);
      },
    );

    test(
      'returns success with remoteActivityId when client returns id > 0',
      () async {
        final client = _FakeIntervalsIcuClient(activityId: 789);
        final uploader = IntervalsIcuFitUploader(client: client);

        final result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.platform, FitUploadPlatform.intervalsIcu);
        expect(result.status, FitUploadPlatformStatus.success);
        expect(result.remoteActivityId, 789);
      },
    );

    test('returns alreadyUploaded when client returns 0', () async {
      final client = _FakeIntervalsIcuClient(activityId: 0);
      final uploader = IntervalsIcuFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
      expect(result.remoteActivityId, isNull);
    });

    test('returns failure on IntervalsIcuRetriableError', () async {
      final client = _FakeIntervalsIcuClient(
        activityId: 0,
        error: const IntervalsIcuRetriableError(
          'intervals.icu upload retriable: 500',
        ),
      );
      final uploader = IntervalsIcuFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.intervalsIcu);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'intervals.icu upload retriable: 500');
    });
  });
}
