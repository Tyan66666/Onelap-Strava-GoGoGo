import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';
import 'package:onelap_strava_sync/services/xingzhe_client.dart';
import 'package:onelap_strava_sync/services/xingzhe_fit_uploader.dart';

class _FakeDetailedXingzheClient extends XingzheClient {
  _FakeDetailedXingzheClient({required this.uploadResult})
    : super(username: 'user', password: 'pass');

  final XingzheUploadFitResult uploadResult;
  int pollCalls = 0;

  @override
  Future<XingzheUploadFitResult> uploadFitDetailed(
    File file, {
    int retries = 3,
  }) async {
    return uploadResult;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) async {
    pollCalls += 1;
    return <String, dynamic>{'status': 'complete', 'activity_id': uploadId};
  }
}

class _FakeXingzheFitUploadClient implements XingzheFitUploadClient {
  _FakeXingzheFitUploadClient({
    required this.uploadResponse,
    required this.pollResult,
  });

  final XingzheFitUploadResponse uploadResponse;
  final Map<String, dynamic> pollResult;
  int uploadCalls = 0;
  int pollCalls = 0;

  @override
  Future<XingzheFitUploadResponse> uploadFit(File file) async {
    uploadCalls += 1;
    return uploadResponse;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) async {
    pollCalls += 1;
    return pollResult;
  }
}

Map<String, String> _settings({String? sessionId}) {
  return <String, String>{
    SettingsService.keyXingzheUsername: 'xingzhe-user',
    SettingsService.keyXingzhePassword: 'xingzhe-password',
    ...?(sessionId == null
        ? null
        : <String, String>{SettingsService.keyXingzheSessionId: sessionId}),
  };
}

void main() {
  group('XingzheFitUploader', () {
    final File testFile = File('/tmp/activity.fit');

    test('existing XINGZHE_SESSION_ID is reused when present', () async {
      final _FakeXingzheFitUploadClient sessionClient =
          _FakeXingzheFitUploadClient(
            uploadResponse: const XingzheFitUploadResponse(uploadId: 222),
            pollResult: <String, dynamic>{
              'status': 'complete',
              'activity_id': 333,
            },
          );
      int sessionFactoryCalls = 0;
      int loginFactoryCalls = 0;
      String? receivedSessionId;
      final XingzheFitUploader uploader = XingzheFitUploader(
        createClientWithSession:
            ({
              required String username,
              required String password,
              required String sessionId,
            }) async {
              sessionFactoryCalls += 1;
              receivedSessionId = sessionId;
              return sessionClient;
            },
        loginClient:
            ({required String username, required String password}) async {
              loginFactoryCalls += 1;
              return sessionClient;
            },
      );

      final FitUploadPlatformResult result = await uploader.upload(
        file: testFile,
        settings: _settings(sessionId: 'cached-session'),
      );

      expect(result.status, FitUploadPlatformStatus.success);
      expect(result.remoteActivityId, 333);
      expect(sessionFactoryCalls, 1);
      expect(loginFactoryCalls, 0);
      expect(receivedSessionId, 'cached-session');
    });

    test(
      'uploader can proceed with username/password when session ID is absent',
      () async {
        final _FakeXingzheFitUploadClient loginClient =
            _FakeXingzheFitUploadClient(
              uploadResponse: const XingzheFitUploadResponse(uploadId: 444),
              pollResult: <String, dynamic>{
                'status': 'complete',
                'activity_id': 555,
              },
            );
        int sessionFactoryCalls = 0;
        int loginFactoryCalls = 0;
        final XingzheFitUploader uploader = XingzheFitUploader(
          createClientWithSession:
              ({
                required String username,
                required String password,
                required String sessionId,
              }) async {
                sessionFactoryCalls += 1;
                return loginClient;
              },
          loginClient:
              ({required String username, required String password}) async {
                loginFactoryCalls += 1;
                return loginClient;
              },
        );

        final FitUploadPlatformResult result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.status, FitUploadPlatformStatus.success);
        expect(result.remoteActivityId, 555);
        expect(sessionFactoryCalls, 0);
        expect(loginFactoryCalls, 1);
      },
    );

    test(
      'duplicate/idempotent Xingzhe response normalizes to alreadyUploaded',
      () async {
        final _FakeXingzheFitUploadClient loginClient =
            _FakeXingzheFitUploadClient(
              uploadResponse: const XingzheFitUploadResponse(
                uploadId: 666,
                alreadyUploaded: true,
                message: '9006 文件已上传',
              ),
              pollResult: <String, dynamic>{
                'status': 'complete',
                'activity_id': 777,
              },
            );
        final XingzheFitUploader uploader = XingzheFitUploader(
          createClientWithSession:
              ({
                required String username,
                required String password,
                required String sessionId,
              }) async {
                return loginClient;
              },
          loginClient:
              ({required String username, required String password}) async {
                return loginClient;
              },
        );

        final FitUploadPlatformResult result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
        expect(result.message, contains('9006'));
        expect(result.remoteActivityId, isNull);
        expect(loginClient.pollCalls, 0);
      },
    );

    test(
      'existing activity id from Xingzhe upload response is normalized to alreadyUploaded',
      () async {
        final _FakeXingzheFitUploadClient loginClient =
            _FakeXingzheFitUploadClient(
              uploadResponse: const XingzheFitUploadResponse(
                uploadId: 0,
                remoteActivityId: 888,
              ),
              pollResult: <String, dynamic>{
                'status': 'complete',
                'activity_id': 888,
              },
            );
        final XingzheFitUploader uploader = XingzheFitUploader(
          createClientWithSession:
              ({
                required String username,
                required String password,
                required String sessionId,
              }) async {
                return loginClient;
              },
          loginClient:
              ({required String username, required String password}) async {
                return loginClient;
              },
        );

        final FitUploadPlatformResult result = await uploader.upload(
          file: testFile,
          settings: _settings(),
        );

        expect(result.status, FitUploadPlatformStatus.alreadyUploaded);
        expect(result.remoteActivityId, 888);
        expect(loginClient.pollCalls, 0);
      },
    );

    test(
      'default adapter preserves duplicate success from Xingzhe client detailed result',
      () async {
        final _FakeDetailedXingzheClient client = _FakeDetailedXingzheClient(
          uploadResult: const XingzheUploadFitResult(
            uploadId: 0,
            remoteActivityId: 999,
            alreadyUploaded: true,
            message: '文件已上传，已存在活动 999',
          ),
        );
        final XingzheFitUploadClient adapter = XingzheFitUploadClientAdapter(
          client,
        );

        final XingzheFitUploadResponse result = await adapter.uploadFit(
          testFile,
        );

        expect(result.alreadyUploaded, isTrue);
        expect(result.remoteActivityId, 999);
        expect(result.message, contains('999'));
      },
    );
  });
}
