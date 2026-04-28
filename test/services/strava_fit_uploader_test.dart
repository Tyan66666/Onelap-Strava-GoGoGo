import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';
import 'package:onelap_strava_sync/services/strava_fit_uploader.dart';

class _FakeStravaFitUploadClient implements StravaFitUploadClient {
  _FakeStravaFitUploadClient({
    required this.uploadId,
    required this.pollResult,
  });

  final int uploadId;
  final Map<String, dynamic> pollResult;
  int uploadCalls = 0;
  int pollCalls = 0;
  final List<File> uploadedFiles = <File>[];
  final List<int> polledUploadIds = <int>[];

  @override
  Future<int> uploadFit(File file) async {
    uploadCalls += 1;
    uploadedFiles.add(file);
    return uploadId;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) async {
    pollCalls += 1;
    polledUploadIds.add(uploadId);
    return pollResult;
  }
}

Map<String, String> _settings() {
  return <String, String>{
    SettingsService.keyStravaClientId: 'client-id',
    SettingsService.keyStravaClientSecret: 'client-secret',
    SettingsService.keyStravaRefreshToken: 'refresh-token',
    SettingsService.keyStravaAccessToken: 'access-token',
    SettingsService.keyStravaExpiresAt: '1234567890',
  };
}

void main() {
  group('StravaFitUploader', () {
    final File testFile = File('/tmp/activity.fit');

    test('poll result with activity_id returns success', () async {
      Map<String, String>? receivedSettings;
      final _FakeStravaFitUploadClient client = _FakeStravaFitUploadClient(
        uploadId: 321,
        pollResult: <String, dynamic>{'status': 'complete', 'activity_id': 654},
      );
      final StravaFitUploader uploader = StravaFitUploader(
        clientFactory: (Map<String, String> settings) {
          receivedSettings = settings;
          return client;
        },
      );

      final FitUploadPlatformResult result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.strava);
      expect(result.status, FitUploadPlatformStatus.success);
      expect(result.remoteActivityId, 654);
      expect(client.uploadCalls, 1);
      expect(client.pollCalls, 1);
      expect(client.uploadedFiles, <File>[testFile]);
      expect(client.polledUploadIds, <int>[321]);
      expect(receivedSettings, _settings());
    });

    test(
      'poll result with duplicate wording returns alreadyUploaded',
      () async {
        final _FakeStravaFitUploadClient client = _FakeStravaFitUploadClient(
          uploadId: 123,
          pollResult: <String, dynamic>{
            'status': 'error',
            'error': 'duplicate of activity 98765',
            'activity_id': null,
          },
        );
        final StravaFitUploader uploader = StravaFitUploader(
          clientFactory: (_) => client,
        );

        final FitUploadPlatformResult result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
        expect(result.message, contains('duplicate'));
        expect(result.remoteActivityId, isNull);
      },
    );

    test(
      'poll result with neither activity_id nor duplicate wording fails as an incomplete upload',
      () async {
        final _FakeStravaFitUploadClient client = _FakeStravaFitUploadClient(
          uploadId: 456,
          pollResult: <String, dynamic>{'status': 'ready', 'activity_id': null},
        );
        final StravaFitUploader uploader = StravaFitUploader(
          clientFactory: (_) => client,
        );

        final FitUploadPlatformResult result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.status, FitUploadPlatformStatus.failure);
        expect(result.message, contains('incomplete'));
      },
    );
  });
}
