import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class _FakeUploader implements FitPlatformUploader {
  _FakeUploader();

  FitUploadPlatformResult? result;

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    return result ??
        FitUploadPlatformResult(
          platform: FitUploadPlatform.outbase,
          status: FitUploadPlatformStatus.success,
        );
  }
}

Map<String, String> _settings({
  bool uploadToOutbase = true,
  String outbaseSessionId = 'test-session',
  bool uploadToStrava = false,
  bool uploadToXingzhe = false,
  bool uploadToIntervalsIcu = false,
}) {
  return <String, String>{
    SettingsService.keyUploadToOutbase: uploadToOutbase.toString(),
    SettingsService.keyOutbaseSessionId: outbaseSessionId,
    SettingsService.keyUploadToStrava: uploadToStrava.toString(),
    SettingsService.keyUploadToXingzhe: uploadToXingzhe.toString(),
    SettingsService.keyUploadToIntervalsIcu: uploadToIntervalsIcu.toString(),
  };
}

void main() {
  group('FitUploadCoordinator Outbase', () {
    group('resolveUploadPlan', () {
      test('includes outbase when UPLOAD_TO_OUTBASE is true', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(_settings());

        expect(plan.targets, contains(FitUploadPlatform.outbase));
      });

      test('does not include outbase when UPLOAD_TO_OUTBASE is false', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(
          _settings(uploadToOutbase: false),
        );

        expect(plan.targets, isNot(contains(FitUploadPlatform.outbase)));
      });
    });

    group('_hasRequiredConfiguration', () {
      test('returns hasMissingConfiguration when sessionId is empty', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(
          _settings(outbaseSessionId: ''),
        );

        expect(plan.hasMissingConfiguration, true);
      });

      test('returns no missing configuration when sessionId is present', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(_settings());

        expect(plan.hasMissingConfiguration, false);
      });
    });

    group('_targetLabel', () {
      test('single platform: Outbase', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(_settings());

        expect(plan.targetLabel, 'Outbase');
      });

      test('two platforms: Strava 和 Outbase', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(
          _settings(uploadToStrava: true),
        );

        expect(plan.targetLabel, 'Strava 和 Outbase');
      });

      test('three platforms', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(
          _settings(uploadToStrava: true, uploadToXingzhe: true),
        );

        expect(plan.targetLabel, contains('Outbase'));
        expect(plan.targetLabel, contains('、'));
      });

      test('four platforms', () {
        final coordinator = FitUploadCoordinator();
        final plan = coordinator.resolveUploadPlan(
          _settings(
            uploadToStrava: true,
            uploadToXingzhe: true,
            uploadToIntervalsIcu: true,
          ),
        );

        expect(plan.targetLabel, contains('Outbase'));
        expect(plan.targetLabel, contains('Strava'));
        expect(plan.targetLabel, contains('行者'));
        expect(plan.targetLabel, contains('Intervals.icu'));
      });
    });

    group('uploadFile', () {
      test('calls outbase uploader when outbase is enabled', () async {
        final fakeUploader = _FakeUploader();
        final coordinator = FitUploadCoordinator(outbaseUploader: fakeUploader);

        final file = File('${Directory.systemTemp.path}/test.fit');
        file.writeAsBytesSync([0x01, 0x02, 0x03]);

        final result = await coordinator.uploadFile(file, _settings());

        expect(result.platformResults.length, 1);
        expect(
          result.platformResults.first.platform,
          FitUploadPlatform.outbase,
        );
        expect(
          result.platformResults.first.status,
          FitUploadPlatformStatus.success,
        );
      });
    });
  });
}
