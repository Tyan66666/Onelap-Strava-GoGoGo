import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';
import 'package:onelap_strava_sync/services/strava_fit_uploader.dart';

class _FakeDefaultStravaFitUploadClient implements StravaFitUploadClient {
  _FakeDefaultStravaFitUploadClient({
    required this.uploadId,
    required this.pollResult,
  });

  final int uploadId;
  final Map<String, dynamic> pollResult;
  int uploadCalls = 0;
  int pollCalls = 0;

  @override
  Future<int> uploadFit(File file) async {
    uploadCalls += 1;
    return uploadId;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) async {
    pollCalls += 1;
    return pollResult;
  }
}

class _FakeFitPlatformUploader implements FitPlatformUploader {
  _FakeFitPlatformUploader({
    required this.platform,
    required this.callOrder,
    required this.result,
    this.error,
  });

  final FitUploadPlatform platform;
  final List<FitUploadPlatform> callOrder;
  final FitUploadPlatformResult result;
  final Exception? error;
  int calls = 0;
  final List<File> receivedFiles = <File>[];
  final List<Map<String, String>> receivedSettings = <Map<String, String>>[];

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    calls += 1;
    callOrder.add(platform);
    receivedFiles.add(file);
    receivedSettings.add(settings);

    if (error != null) {
      throw error!;
    }

    return result;
  }
}

Map<String, String> _settings({
  String uploadToStrava = 'false',
  String uploadToXingzhe = 'false',
  String stravaClientId = 'client-id',
  String stravaClientSecret = 'client-secret',
  String stravaRefreshToken = 'refresh-token',
  String xingzheUsername = 'xingzhe-user',
  String xingzhePassword = 'xingzhe-password',
}) {
  return <String, String>{
    SettingsService.keyUploadToStrava: uploadToStrava,
    SettingsService.keyUploadToXingzhe: uploadToXingzhe,
    SettingsService.keyStravaClientId: stravaClientId,
    SettingsService.keyStravaClientSecret: stravaClientSecret,
    SettingsService.keyStravaRefreshToken: stravaRefreshToken,
    SettingsService.keyXingzheUsername: xingzheUsername,
    SettingsService.keyXingzhePassword: xingzhePassword,
  };
}

FitUploadCoordinator _buildCoordinator({
  required _FakeFitPlatformUploader stravaUploader,
  required _FakeFitPlatformUploader xingzheUploader,
}) {
  return FitUploadCoordinator(
    stravaUploader: stravaUploader,
    xingzheUploader: xingzheUploader,
  );
}

void main() {
  group('FitUploadCoordinator', () {
    final File testFile = File('/tmp/activity.fit');

    test('Strava-only settings call only the Strava uploader', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToStrava: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.success);
      expect(result.hasPartialFailure, isFalse);
      expect(result.allPlatformsSucceeded, isTrue);
      expect(
        result.platformResults.map((result) => result.platform),
        <FitUploadPlatform>[FitUploadPlatform.strava],
      );
      expect(
        () => result.platformResults.add(
          const FitUploadPlatformResult(
            platform: FitUploadPlatform.strava,
            status: FitUploadPlatformStatus.success,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(stravaUploader.calls, 1);
      expect(xingzheUploader.calls, 0);
      expect(callOrder, <FitUploadPlatform>[FitUploadPlatform.strava]);
      expect(stravaUploader.receivedFiles, <File>[testFile]);
      expect(stravaUploader.receivedSettings, <Map<String, String>>[
        _settings(uploadToStrava: 'true'),
      ]);
    });

    test('Xingzhe-only settings call only the Xingzhe uploader', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToXingzhe: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.success);
      expect(
        result.platformResults.map((result) => result.platform),
        <FitUploadPlatform>[FitUploadPlatform.xingzhe],
      );
      expect(stravaUploader.calls, 0);
      expect(xingzheUploader.calls, 1);
      expect(callOrder, <FitUploadPlatform>[FitUploadPlatform.xingzhe]);
    });

    test('Both toggles enabled call both uploaders in order', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToStrava: 'true', uploadToXingzhe: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.success);
      expect(
        result.platformResults.map((result) => result.platform),
        <FitUploadPlatform>[
          FitUploadPlatform.strava,
          FitUploadPlatform.xingzhe,
        ],
      );
      expect(stravaUploader.calls, 1);
      expect(xingzheUploader.calls, 1);
      expect(callOrder, <FitUploadPlatform>[
        FitUploadPlatform.strava,
        FitUploadPlatform.xingzhe,
      ]);
    });

    test('Values like TRUE and " true " are treated as enabled', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadPlan plan = coordinator.resolveUploadPlan(
        _settings(uploadToStrava: ' TRUE ', uploadToXingzhe: ' true '),
      );

      expect(plan.targets, <FitUploadPlatform>[
        FitUploadPlatform.strava,
        FitUploadPlatform.xingzhe,
      ]);
      expect(plan.hasMissingConfiguration, isFalse);
      expect(
        () => plan.targets.add(FitUploadPlatform.strava),
        throwsUnsupportedError,
      );
    });

    test(
      'No enabled targets produces a preflight plan with hasMissingConfiguration == true and no upload attempts',
      () async {
        final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
        final _FakeFitPlatformUploader stravaUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.strava,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.strava,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final _FakeFitPlatformUploader xingzheUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.xingzhe,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.xingzhe,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final FitUploadCoordinator coordinator = _buildCoordinator(
          stravaUploader: stravaUploader,
          xingzheUploader: xingzheUploader,
        );

        final FitUploadPlan plan = coordinator.resolveUploadPlan(_settings());
        final FitUploadCoordinatorResult result = await coordinator.uploadFile(
          testFile,
          _settings(),
        );

        expect(plan.targets, isEmpty);
        expect(plan.hasMissingConfiguration, isTrue);
        expect(result.status, FitUploadCoordinatorStatus.missingConfiguration);
        expect(result.platformResults, isEmpty);
        expect(stravaUploader.calls, 0);
        expect(xingzheUploader.calls, 0);
        expect(callOrder, isEmpty);
      },
    );

    test(
      'Strava enabled with missing Strava credentials blocks upload before any uploader runs',
      () async {
        final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
        final _FakeFitPlatformUploader stravaUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.strava,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.strava,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final _FakeFitPlatformUploader xingzheUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.xingzhe,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.xingzhe,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final FitUploadCoordinator coordinator = _buildCoordinator(
          stravaUploader: stravaUploader,
          xingzheUploader: xingzheUploader,
        );
        final Map<String, String> settings = _settings(
          uploadToStrava: 'true',
          stravaClientSecret: '',
        );

        final FitUploadCoordinatorResult result = await coordinator.uploadFile(
          testFile,
          settings,
        );

        expect(result.status, FitUploadCoordinatorStatus.missingConfiguration);
        expect(result.platformResults, isEmpty);
        expect(stravaUploader.calls, 0);
        expect(xingzheUploader.calls, 0);
        expect(callOrder, isEmpty);
      },
    );

    test(
      'Xingzhe enabled with missing Xingzhe credentials blocks upload before any uploader runs',
      () async {
        final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
        final _FakeFitPlatformUploader stravaUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.strava,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.strava,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final _FakeFitPlatformUploader xingzheUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.xingzhe,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.xingzhe,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final FitUploadCoordinator coordinator = _buildCoordinator(
          stravaUploader: stravaUploader,
          xingzheUploader: xingzheUploader,
        );
        final Map<String, String> settings = _settings(
          uploadToXingzhe: 'true',
          xingzhePassword: '',
        );

        final FitUploadCoordinatorResult result = await coordinator.uploadFile(
          testFile,
          settings,
        );

        expect(result.status, FitUploadCoordinatorStatus.missingConfiguration);
        expect(result.platformResults, isEmpty);
        expect(stravaUploader.calls, 0);
        expect(xingzheUploader.calls, 0);
        expect(callOrder, isEmpty);
      },
    );

    test(
      'Both enabled with missing Xingzhe credentials blocks upload before any uploader runs',
      () async {
        final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
        final _FakeFitPlatformUploader stravaUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.strava,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.strava,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final _FakeFitPlatformUploader xingzheUploader =
            _FakeFitPlatformUploader(
              platform: FitUploadPlatform.xingzhe,
              callOrder: callOrder,
              result: const FitUploadPlatformResult(
                platform: FitUploadPlatform.xingzhe,
                status: FitUploadPlatformStatus.success,
              ),
            );
        final FitUploadCoordinator coordinator = _buildCoordinator(
          stravaUploader: stravaUploader,
          xingzheUploader: xingzheUploader,
        );
        final Map<String, String> settings = _settings(
          uploadToStrava: 'true',
          uploadToXingzhe: 'true',
          xingzheUsername: '',
        );

        final FitUploadCoordinatorResult result = await coordinator.uploadFile(
          testFile,
          settings,
        );

        expect(result.status, FitUploadCoordinatorStatus.missingConfiguration);
        expect(result.platformResults, isEmpty);
        expect(stravaUploader.calls, 0);
        expect(xingzheUploader.calls, 0);
        expect(callOrder, isEmpty);
      },
    );

    test('Both uploaders receive the same file and settings handoff', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );
      final Map<String, String> settings = _settings(
        uploadToStrava: 'true',
        uploadToXingzhe: 'true',
      );

      await coordinator.uploadFile(testFile, settings);

      expect(stravaUploader.receivedFiles, <File>[testFile]);
      expect(xingzheUploader.receivedFiles, <File>[testFile]);
      expect(stravaUploader.receivedSettings.single, settings);
      expect(xingzheUploader.receivedSettings.single, settings);
    });

    test('Strava failure still allows Xingzhe to run', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.success,
        ),
        error: Exception('Strava failed'),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToStrava: 'true', uploadToXingzhe: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.partialSuccess);
      expect(result.hasPartialFailure, isTrue);
      expect(result.allPlatformsSucceeded, isFalse);
      expect(
        result.platformResults.map((result) => result.status),
        <FitUploadPlatformStatus>[
          FitUploadPlatformStatus.failure,
          FitUploadPlatformStatus.success,
        ],
      );
      expect(stravaUploader.calls, 1);
      expect(xingzheUploader.calls, 1);
      expect(callOrder, <FitUploadPlatform>[
        FitUploadPlatform.strava,
        FitUploadPlatform.xingzhe,
      ]);
    });

    test('alreadyUploaded counts toward aggregate success', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.alreadyUploaded,
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.success,
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToStrava: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.success);
      expect(result.hasSuccessfulUpload, isTrue);
      expect(result.hasPartialFailure, isFalse);
      expect(result.allPlatformsSucceeded, isTrue);
      expect(
        result.platformResults.single.status,
        FitUploadPlatformStatus.alreadyUploaded,
      );
      expect(stravaUploader.calls, 1);
      expect(xingzheUploader.calls, 0);
    });

    test(
      'default concrete Strava uploader alreadyUploaded counts toward aggregate success',
      () async {
        final _FakeDefaultStravaFitUploadClient client =
            _FakeDefaultStravaFitUploadClient(
              uploadId: 123,
              pollResult: <String, dynamic>{
                'status': 'error',
                'error': 'duplicate of activity 98765',
                'activity_id': null,
              },
            );
        final FitUploadCoordinator coordinator = FitUploadCoordinator(
          stravaClientFactory: (_) => client,
        );

        final FitUploadCoordinatorResult result = await coordinator.uploadFile(
          testFile,
          _settings(uploadToStrava: 'true'),
        );

        expect(result.status, FitUploadCoordinatorStatus.success);
        expect(result.hasSuccessfulUpload, isTrue);
        expect(
          result.platformResults.single.status,
          FitUploadPlatformStatus.alreadyUploaded,
        );
        expect(client.uploadCalls, 1);
        expect(client.pollCalls, 1);
      },
    );

    test('All failed attempts produce an aggregate failure result', () async {
      final List<FitUploadPlatform> callOrder = <FitUploadPlatform>[];
      final _FakeFitPlatformUploader stravaUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.strava,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.strava,
          status: FitUploadPlatformStatus.failure,
          message: 'strava failed',
        ),
      );
      final _FakeFitPlatformUploader xingzheUploader = _FakeFitPlatformUploader(
        platform: FitUploadPlatform.xingzhe,
        callOrder: callOrder,
        result: const FitUploadPlatformResult(
          platform: FitUploadPlatform.xingzhe,
          status: FitUploadPlatformStatus.failure,
          message: 'xingzhe failed',
        ),
      );
      final FitUploadCoordinator coordinator = _buildCoordinator(
        stravaUploader: stravaUploader,
        xingzheUploader: xingzheUploader,
      );

      final FitUploadCoordinatorResult result = await coordinator.uploadFile(
        testFile,
        _settings(uploadToStrava: 'true', uploadToXingzhe: 'true'),
      );

      expect(result.status, FitUploadCoordinatorStatus.failure);
      expect(result.hasSuccessfulUpload, isFalse);
      expect(result.hasPartialFailure, isFalse);
      expect(result.allPlatformsSucceeded, isFalse);
      expect(
        result.platformResults.map((result) => result.platform),
        <FitUploadPlatform>[
          FitUploadPlatform.strava,
          FitUploadPlatform.xingzhe,
        ],
      );
      expect(stravaUploader.calls, 1);
      expect(xingzheUploader.calls, 1);
    });
  });
}
