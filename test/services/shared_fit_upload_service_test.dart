import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/shared_fit_draft.dart';
import 'package:onelap_strava_sync/services/fit_coordinate_rewrite_service.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';
import 'package:onelap_strava_sync/services/shared_fit_upload_service.dart';

class _FakeFitCoordinateRewriteService extends FitCoordinateRewriteService {
  _FakeFitCoordinateRewriteService({this.rewriteFile, this.error});

  final File? rewriteFile;
  final Exception? error;
  File? receivedFile;

  @override
  Future<File> rewrite(File inputFile, {RewriteOptions? options}) async {
    receivedFile = inputFile;
    if (error != null) {
      throw error!;
    }
    return rewriteFile!;
  }
}

class _FakeFitUploadCoordinator extends FitUploadCoordinator {
  _FakeFitUploadCoordinator({
    FitUploadPlan? plan,
    FitUploadCoordinatorResult? result,
  }) : plan =
           plan ??
           FitUploadPlan(
             targets: <FitUploadPlatform>[FitUploadPlatform.strava],
             hasMissingConfiguration: false,
             targetLabel: 'Strava',
           ),
       result =
           result ??
           FitUploadCoordinatorResult(
             status: FitUploadCoordinatorStatus.success,
             platformResults: <FitUploadPlatformResult>[
               const FitUploadPlatformResult(
                 platform: FitUploadPlatform.strava,
                 status: FitUploadPlatformStatus.success,
               ),
             ],
           );

  FitUploadPlan plan;
  FitUploadCoordinatorResult result;
  File? uploadedFile;
  Map<String, String>? uploadedSettings;
  int resolveUploadPlanCalls = 0;
  int uploadFileCalls = 0;

  @override
  FitUploadPlan resolveUploadPlan(Map<String, String> settings) {
    resolveUploadPlanCalls += 1;
    return plan;
  }

  @override
  Future<FitUploadCoordinatorResult> uploadFile(
    File file,
    Map<String, String> settings,
  ) async {
    uploadFileCalls += 1;
    uploadedFile = file;
    uploadedSettings = settings;
    return result;
  }
}

Map<String, String> _settings({
  String uploadToStrava = 'true',
  String uploadToXingzhe = 'false',
  String gcjCorrectionEnabled = 'false',
}) {
  return <String, String>{
    SettingsService.keyUploadToStrava: uploadToStrava,
    SettingsService.keyUploadToXingzhe: uploadToXingzhe,
    SettingsService.keyGcjCorrectionEnabled: gcjCorrectionEnabled,
    SettingsService.keyStravaClientId: 'client-id',
    SettingsService.keyStravaClientSecret: 'client-secret',
    SettingsService.keyStravaRefreshToken: 'refresh-token',
    SettingsService.keyXingzheUsername: 'username',
    SettingsService.keyXingzhePassword: 'password',
  };
}

Future<File> _createFitFile(Directory tempDir, {String name = 'activity.fit'}) {
  final File fitFile = File('${tempDir.path}/$name');
  return fitFile.writeAsBytes(<int>[1, 2, 3]);
}

void main() {
  group('SharedFitUploadService.loadUploadPlan', () {
    test('returns a Strava target label from coordinator preflight', () async {
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
        plan: FitUploadPlan(
          targets: <FitUploadPlatform>[FitUploadPlatform.strava],
          hasMissingConfiguration: false,
          targetLabel: 'Strava',
        ),
      );
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(uploadToStrava: 'true'),
        coordinator: coordinator,
      );

      final FitUploadPlan plan = await service.loadUploadPlan();

      expect(plan.targetLabel, 'Strava');
      expect(coordinator.resolveUploadPlanCalls, 1);
    });

    test('returns a Xingzhe target label from coordinator preflight', () async {
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
        plan: FitUploadPlan(
          targets: <FitUploadPlatform>[FitUploadPlatform.xingzhe],
          hasMissingConfiguration: false,
          targetLabel: '行者',
        ),
      );
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async =>
            _settings(uploadToStrava: 'false', uploadToXingzhe: 'true'),
        coordinator: coordinator,
      );

      final FitUploadPlan plan = await service.loadUploadPlan();

      expect(plan.targetLabel, '行者');
      expect(coordinator.resolveUploadPlanCalls, 1);
    });

    test(
      'returns a dual-platform target label from coordinator preflight',
      () async {
        final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
          plan: FitUploadPlan(
            targets: <FitUploadPlatform>[
              FitUploadPlatform.strava,
              FitUploadPlatform.xingzhe,
            ],
            hasMissingConfiguration: false,
            targetLabel: 'Strava 和行者',
          ),
        );
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async =>
              _settings(uploadToStrava: 'true', uploadToXingzhe: 'true'),
          coordinator: coordinator,
        );

        final FitUploadPlan plan = await service.loadUploadPlan();

        expect(plan.targetLabel, 'Strava 和行者');
        expect(coordinator.resolveUploadPlanCalls, 1);
      },
    );
  });

  group('SharedFitUploadService.uploadDraft', () {
    test('returns invalidFile for a non-fit extension', () async {
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator();
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(),
        coordinator: coordinator,
      );

      const SharedFitDraft draft = SharedFitDraft(
        localFilePath: '/tmp/activity.gpx',
        displayName: 'activity.gpx',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.invalidFile);
      expect(coordinator.resolveUploadPlanCalls, 0);
      expect(coordinator.uploadFileCalls, 0);
    });

    test('returns invalidFile when the local file is not readable', () async {
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator();
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(),
        coordinator: coordinator,
      );

      const SharedFitDraft draft = SharedFitDraft(
        localFilePath: '/tmp/missing.fit',
        displayName: 'missing.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.invalidFile);
      expect(coordinator.resolveUploadPlanCalls, 0);
      expect(coordinator.uploadFileCalls, 0);
    });

    test(
      'returns missingConfiguration when no upload targets are enabled',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-missing-config-',
        );
        final File fitFile = await _createFitFile(tempDir);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
          plan: FitUploadPlan(
            targets: const <FitUploadPlatform>[],
            hasMissingConfiguration: true,
            targetLabel: '',
          ),
        );
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async =>
              _settings(uploadToStrava: 'false', uploadToXingzhe: 'false'),
          coordinator: coordinator,
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'activity.fit',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.missingConfiguration);
        expect(coordinator.resolveUploadPlanCalls, 1);
        expect(coordinator.uploadFileCalls, 0);
      },
    );

    test(
      'accepts a fit localFilePath when displayName lacks the fit extension',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-display-name-mismatch-',
        );
        final File fitFile = await _createFitFile(tempDir);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final _FakeFitUploadCoordinator coordinator =
            _FakeFitUploadCoordinator();
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => _settings(),
          coordinator: coordinator,
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'shared_from_onelap',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.success);
        expect(coordinator.uploadedFile, isNotNull);
        expect(coordinator.uploadedFile!.path, fitFile.path);
      },
    );

    test('returns failure when loading settings throws', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-settings-failure-',
      );
      final File fitFile = await _createFitFile(tempDir);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator();
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async {
          throw Exception('settings unavailable');
        },
        coordinator: coordinator,
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'Failed to load settings: settings unavailable');
      expect(coordinator.resolveUploadPlanCalls, 0);
      expect(coordinator.uploadFileCalls, 0);
    });

    test('delegates the original file when GCJ rewrite is disabled', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-disabled-',
      );
      final File fitFile = await _createFitFile(tempDir);
      final File rewrittenFile = await _createFitFile(
        tempDir,
        name: 'rewritten.fit',
      );

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator();
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(gcjCorrectionEnabled: 'false'),
        rewriteService: rewriteService,
        coordinator: coordinator,
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(rewriteService.receivedFile, isNull);
      expect(coordinator.uploadedFile, isNotNull);
      expect(coordinator.uploadedFile!.path, fitFile.path);
    });

    test(
      'rewrites the file before delegating upload when GCJ rewrite is enabled',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-rewrite-enabled-',
        );
        final File fitFile = await _createFitFile(tempDir);
        final File rewrittenFile = await _createFitFile(
          tempDir,
          name: 'rewritten.fit',
        );

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final _FakeFitCoordinateRewriteService rewriteService =
            _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
        final _FakeFitUploadCoordinator coordinator =
            _FakeFitUploadCoordinator();
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => _settings(gcjCorrectionEnabled: 'true'),
          rewriteService: rewriteService,
          coordinator: coordinator,
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'activity.fit',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.success);
        expect(rewriteService.receivedFile, isNotNull);
        expect(rewriteService.receivedFile!.path, fitFile.path);
        expect(coordinator.uploadedFile, isNotNull);
        expect(coordinator.uploadedFile!.path, rewrittenFile.path);
      },
    );

    test(
      'deletes rewritten temp files after the delegated upload attempt',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-rewrite-cleanup-',
        );
        final File fitFile = await _createFitFile(tempDir);
        final Directory rewrittenDir = await Directory.systemTemp.createTemp(
          'fit-coordinate-rewrite-',
        );
        final File rewrittenFile = await _createFitFile(
          rewrittenDir,
          name: 'rewritten.fit',
        );

        addTearDown(() async {
          if (await rewrittenDir.exists()) {
            await rewrittenDir.delete(recursive: true);
          }
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final _FakeFitCoordinateRewriteService rewriteService =
            _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
        final _FakeFitUploadCoordinator coordinator =
            _FakeFitUploadCoordinator();
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => _settings(gcjCorrectionEnabled: 'true'),
          rewriteService: rewriteService,
          coordinator: coordinator,
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'activity.fit',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.success);
        expect(await fitFile.exists(), isTrue);
        expect(await rewrittenFile.exists(), isFalse);
        expect(await rewrittenDir.exists(), isTrue);
      },
    );

    test('returns failure when GCJ rewrite throws', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-failure-',
      );
      final File fitFile = await _createFitFile(tempDir);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(error: Exception('rewrite failed'));
      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator();
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(gcjCorrectionEnabled: 'true'),
        rewriteService: rewriteService,
        coordinator: coordinator,
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'FIT coordinate rewrite failed: rewrite failed');
      expect(coordinator.uploadFileCalls, 0);
    });

    test('returns success with a partial-success message', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-partial-success-',
      );
      final File fitFile = await _createFitFile(tempDir);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
        plan: FitUploadPlan(
          targets: <FitUploadPlatform>[
            FitUploadPlatform.strava,
            FitUploadPlatform.xingzhe,
          ],
          hasMissingConfiguration: false,
          targetLabel: 'Strava 和行者',
        ),
        result: FitUploadCoordinatorResult(
          status: FitUploadCoordinatorStatus.partialSuccess,
          platformResults: const <FitUploadPlatformResult>[
            FitUploadPlatformResult(
              platform: FitUploadPlatform.strava,
              status: FitUploadPlatformStatus.success,
            ),
            FitUploadPlatformResult(
              platform: FitUploadPlatform.xingzhe,
              status: FitUploadPlatformStatus.failure,
              message: 'session expired',
            ),
          ],
        ),
      );
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async =>
            _settings(uploadToStrava: 'true', uploadToXingzhe: 'true'),
        coordinator: coordinator,
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(result.message, '已上传到 Strava；行者上传失败：session expired');
    });

    test('returns failure when all delegated uploads fail', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-failure-',
      );
      final File fitFile = await _createFitFile(tempDir);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitUploadCoordinator coordinator = _FakeFitUploadCoordinator(
        plan: FitUploadPlan(
          targets: <FitUploadPlatform>[
            FitUploadPlatform.strava,
            FitUploadPlatform.xingzhe,
          ],
          hasMissingConfiguration: false,
          targetLabel: 'Strava 和行者',
        ),
        result: FitUploadCoordinatorResult(
          status: FitUploadCoordinatorStatus.failure,
          platformResults: const <FitUploadPlatformResult>[
            FitUploadPlatformResult(
              platform: FitUploadPlatform.strava,
              status: FitUploadPlatformStatus.failure,
              message: 'upload failed',
            ),
            FitUploadPlatformResult(
              platform: FitUploadPlatform.xingzhe,
              status: FitUploadPlatformStatus.failure,
              message: 'session expired',
            ),
          ],
        ),
      );
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => _settings(),
        coordinator: coordinator,
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'Strava上传失败：upload failed；行者上传失败：session expired');
    });
  });
}
