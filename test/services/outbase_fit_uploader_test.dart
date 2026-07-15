import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/outbase_client.dart';
import 'package:onelap_strava_sync/services/outbase_fit_uploader.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class _FakeOutbaseClient extends OutbaseClient {
  _FakeOutbaseClient({required this.result, this.error})
    : super(sessionId: 'fake');

  final OutbaseUploadResult result;
  final Exception? error;

  @override
  Future<OutbaseUploadResult> uploadFit(File file) async {
    if (error != null) throw error!;
    return result;
  }
}

Map<String, String> _settings({String sessionId = 'test-session-id'}) {
  return <String, String>{SettingsService.keyOutbaseSessionId: sessionId};
}

void main() {
  group('OutbaseFitUploader', () {
    late File testFile;

    setUp(() {
      testFile = File('${Directory.systemTemp.path}/outbase_test.fit');
      testFile.writeAsBytesSync([0x01, 0x02, 0x03]);
    });

    tearDown(() {
      if (testFile.existsSync()) {
        testFile.deleteSync();
      }
    });

    test('returns failure when sessionId is empty', () async {
      final uploader = OutbaseFitUploader();

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(sessionId: ''),
      );

      expect(result.platform, FitUploadPlatform.outbase);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'Outbase 未登录，请先在设置中登录');
    });

    test('returns success when upload succeeds', () async {
      final client = _FakeOutbaseClient(
        result: const OutbaseUploadResult(
          success: true,
          alreadyUploaded: false,
        ),
      );
      final uploader = OutbaseFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.outbase);
      expect(result.status, FitUploadPlatformStatus.success);
    });

    test('returns alreadyUploaded when activity already exists', () async {
      final client = _FakeOutbaseClient(
        result: const OutbaseUploadResult(
          success: false,
          alreadyUploaded: true,
          message: '相同时间内已存在其他运动数据',
        ),
      );
      final uploader = OutbaseFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.outbase);
      expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
    });

    test('returns failure on OutbasePermanentError', () async {
      final client = _FakeOutbaseClient(
        result: const OutbaseUploadResult(
          success: false,
          alreadyUploaded: false,
        ),
        error: const OutbasePermanentError('session expired'),
      );
      final uploader = OutbaseFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.outbase);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'session expired');
    });

    test('returns failure on OutbaseRetriableError', () async {
      final client = _FakeOutbaseClient(
        result: const OutbaseUploadResult(
          success: false,
          alreadyUploaded: false,
        ),
        error: const OutbaseRetriableError('network timeout'),
      );
      final uploader = OutbaseFitUploader(client: client);

      final result = await uploader.upload(
        file: testFile,
        settings: _settings(),
      );

      expect(result.platform, FitUploadPlatform.outbase);
      expect(result.status, FitUploadPlatformStatus.failure);
      expect(result.message, 'network timeout');
    });
  });
}
