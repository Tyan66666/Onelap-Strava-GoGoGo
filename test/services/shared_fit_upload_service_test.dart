import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/shared_fit_draft.dart';
import 'package:onelap_strava_sync/services/fit_coordinate_rewrite_service.dart';
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

Map<String, String> _validStravaSettings({
  String gcjCorrectionEnabled = 'false',
}) {
  return <String, String>{
    SettingsService.keyStravaClientId: 'client-id',
    SettingsService.keyStravaClientSecret: 'client-secret',
    SettingsService.keyStravaRefreshToken: 'refresh-token',
    SettingsService.keyGcjCorrectionEnabled: gcjCorrectionEnabled,
  };
}

void main() {
  group('SharedFitUploadService.uploadDraft', () {
    test(
      'returns missingConfiguration when Strava settings are incomplete',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-missing-config-',
        );
        final File fitFile = File('${tempDir.path}/activity.fit');
        await fitFile.writeAsBytes(<int>[1, 2, 3]);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => <String, String>{
            SettingsService.keyStravaClientId: '',
            SettingsService.keyStravaClientSecret: 'client-secret',
            SettingsService.keyStravaRefreshToken: 'refresh-token',
          },
          executeUpload:
              ({required File file, required Map<String, String> settings}) {
                fail(
                  'executeUpload should not be called when configuration is missing',
                );
              },
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'activity.fit',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.missingConfiguration);
      },
    );

    test('returns invalidFile for a non-fit extension', () async {
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
        },
        executeUpload:
            ({required File file, required Map<String, String> settings}) {
              fail('executeUpload should not be called for invalid files');
            },
      );

      const SharedFitDraft draft = SharedFitDraft(
        localFilePath: '/tmp/activity.gpx',
        displayName: 'activity.gpx',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.invalidFile);
    });

    test('returns invalidFile when the local file is not readable', () async {
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
        },
        executeUpload:
            ({required File file, required Map<String, String> settings}) {
              fail('executeUpload should not be called for unreadable files');
            },
      );

      const SharedFitDraft draft = SharedFitDraft(
        localFilePath: '/tmp/missing.fit',
        displayName: 'missing.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.invalidFile);
    });

    test(
      'accepts a fit localFilePath when displayName lacks the fit extension',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-display-name-mismatch-',
        );
        final File fitFile = File('${tempDir.path}/activity.fit');
        await fitFile.writeAsBytes(<int>[1, 2, 3]);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        File? uploadedFile;
        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => _validStravaSettings(),
          executeUpload:
              ({
                required File file,
                required Map<String, String> settings,
              }) async {
                uploadedFile = file;
              },
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'shared_from_onelap',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.success);
        expect(uploadedFile, isNotNull);
        expect(uploadedFile!.path, fitFile.path);
      },
    );

    test('returns failure when loading settings throws', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-settings-failure-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async {
          throw Exception('settings unavailable');
        },
        executeUpload:
            ({required File file, required Map<String, String> settings}) {
              fail(
                'executeUpload should not be called when loading settings fails',
              );
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'Failed to load settings: settings unavailable');
    });

    test('returns success after the upload flow completes', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-success-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      File? uploadedFile;
      bool completed = false;
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
        },
        executeUpload:
            ({
              required File file,
              required Map<String, String> settings,
            }) async {
              uploadedFile = file;
              await Future<void>.delayed(Duration.zero);
              completed = true;
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(uploadedFile, isNotNull);
      expect(uploadedFile!.path, fitFile.path);
      expect(completed, isTrue);
    });

    test('uploads the original file when GCJ rewrite is disabled', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-disabled-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${tempDir.path}/rewritten.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
      File? uploadedFile;
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
          SettingsService.keyGcjCorrectionEnabled: 'false',
        },
        rewriteService: rewriteService,
        executeUpload:
            ({
              required File file,
              required Map<String, String> settings,
            }) async {
              uploadedFile = file;
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(rewriteService.receivedFile, isNull);
      expect(uploadedFile, isNotNull);
      expect(uploadedFile!.path, fitFile.path);
    });

    test('uploads the rewritten file when GCJ rewrite is enabled', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-enabled-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${tempDir.path}/rewritten.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
      File? uploadedFile;
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
          SettingsService.keyGcjCorrectionEnabled: 'true',
        },
        rewriteService: rewriteService,
        executeUpload:
            ({
              required File file,
              required Map<String, String> settings,
            }) async {
              uploadedFile = file;
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(rewriteService.receivedFile, isNotNull);
      expect(rewriteService.receivedFile!.path, fitFile.path);
      expect(uploadedFile, isNotNull);
      expect(uploadedFile!.path, rewrittenFile.path);
    });

    test('deletes the rewritten temp file after the upload attempt', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-cleanup-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${tempDir.path}/rewritten.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(rewriteFile: rewrittenFile);
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async =>
            _validStravaSettings(gcjCorrectionEnabled: 'true'),
        rewriteService: rewriteService,
        executeUpload:
            ({
              required File file,
              required Map<String, String> settings,
            }) async {
              expect(file.path, rewrittenFile.path);
              expect(await rewrittenFile.exists(), isTrue);
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.success);
      expect(await fitFile.exists(), isTrue);
      expect(await rewrittenFile.exists(), isFalse);
    });

    test('returns failure when GCJ rewrite throws', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-rewrite-failure-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(error: Exception('rewrite failed'));
      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
          SettingsService.keyGcjCorrectionEnabled: 'true',
        },
        rewriteService: rewriteService,
        executeUpload:
            ({required File file, required Map<String, String> settings}) {
              fail('executeUpload should not be called when rewrite fails');
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'FIT coordinate rewrite failed: rewrite failed');
    });

    test('returns failure when the upload flow throws', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'shared-fit-upload-failure-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final SharedFitUploadService service = SharedFitUploadService(
        loadSettings: () async => <String, String>{
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
        },
        executeUpload:
            ({
              required File file,
              required Map<String, String> settings,
            }) async {
              throw Exception('upload failed');
            },
      );

      final SharedFitDraft draft = SharedFitDraft(
        localFilePath: fitFile.path,
        displayName: 'activity.fit',
      );

      final SharedFitUploadResult result = await service.uploadDraft(draft);

      expect(result.status, SharedFitUploadStatus.failure);
      expect(result.message, 'upload failed');
    });

    test(
      'returns failure when upload succeeds but polling result is not ready',
      () async {
        final Directory tempDir = await Directory.systemTemp.createTemp(
          'shared-fit-upload-poll-failure-',
        );
        final File fitFile = File('${tempDir.path}/activity.fit');
        await fitFile.writeAsBytes(<int>[1, 2, 3]);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final SharedFitUploadService service = SharedFitUploadService(
          loadSettings: () async => <String, String>{
            SettingsService.keyStravaClientId: 'client-id',
            SettingsService.keyStravaClientSecret: 'client-secret',
            SettingsService.keyStravaRefreshToken: 'refresh-token',
          },
          executeUpload:
              ({
                required File file,
                required Map<String, String> settings,
              }) async {
                throw Exception('Strava is still processing the upload');
              },
        );

        final SharedFitDraft draft = SharedFitDraft(
          localFilePath: fitFile.path,
          displayName: 'activity.fit',
        );

        final SharedFitUploadResult result = await service.uploadDraft(draft);

        expect(result.status, SharedFitUploadStatus.failure);
        expect(result.message, 'Strava is still processing the upload');
      },
    );
  });
}
