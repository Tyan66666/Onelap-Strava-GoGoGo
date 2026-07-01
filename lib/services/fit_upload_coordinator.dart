import 'dart:io';

import 'intervals_icu_fit_uploader.dart';
import 'settings_service.dart';
import 'strava_fit_uploader.dart';
import 'xingzhe_fit_uploader.dart';

enum FitUploadPlatform { strava, xingzhe, intervalsIcu }

enum FitUploadPlatformStatus { success, alreadyUploaded, failure }

enum FitUploadCoordinatorStatus {
  success,
  partialSuccess,
  failure,
  missingConfiguration,
}

class FitUploadPlatformResult {
  const FitUploadPlatformResult({
    required this.platform,
    required this.status,
    this.message,
    this.remoteActivityId,
  });

  final FitUploadPlatform platform;
  final FitUploadPlatformStatus status;
  final String? message;
  final int? remoteActivityId;
}

class FitUploadPlan {
  FitUploadPlan({
    required List<FitUploadPlatform> targets,
    required this.hasMissingConfiguration,
    required this.targetLabel,
  }) : targets = List<FitUploadPlatform>.unmodifiable(targets);

  final List<FitUploadPlatform> targets;
  final bool hasMissingConfiguration;
  final String targetLabel;
}

class FitUploadCoordinatorResult {
  FitUploadCoordinatorResult({
    required this.status,
    required List<FitUploadPlatformResult> platformResults,
  }) : platformResults = List<FitUploadPlatformResult>.unmodifiable(
         platformResults,
       );

  final FitUploadCoordinatorStatus status;
  final List<FitUploadPlatformResult> platformResults;

  bool get hasSuccessfulUpload {
    return platformResults.any(
      (FitUploadPlatformResult result) =>
          result.status == FitUploadPlatformStatus.success ||
          result.status == FitUploadPlatformStatus.alreadyUploaded,
    );
  }

  bool get hasPartialFailure {
    return hasSuccessfulUpload &&
        platformResults.any(
          (FitUploadPlatformResult result) =>
              result.status == FitUploadPlatformStatus.failure,
        );
  }

  bool get allPlatformsSucceeded {
    return platformResults.isNotEmpty &&
        platformResults.every(
          (FitUploadPlatformResult result) =>
              result.status == FitUploadPlatformStatus.success ||
              result.status == FitUploadPlatformStatus.alreadyUploaded,
        );
  }
}

abstract class FitPlatformUploader {
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  });
}

class FitUploadCoordinator {
  FitUploadCoordinator({
    FitPlatformUploader? stravaUploader,
    FitPlatformUploader? xingzheUploader,
    FitPlatformUploader? intervalsIcuUploader,
    StravaFitUploadClientFactory? stravaClientFactory,
    XingzheSessionClientFactory? xingzheSessionClientFactory,
    XingzheLoginClientFactory? xingzheLoginClientFactory,
  }) : _stravaUploader =
           stravaUploader ??
           StravaFitUploader(clientFactory: stravaClientFactory),
       _xingzheUploader =
           xingzheUploader ??
           XingzheFitUploader(
             createClientWithSession: xingzheSessionClientFactory,
             loginClient: xingzheLoginClientFactory,
           ),
       _intervalsIcuUploader =
           intervalsIcuUploader ?? IntervalsIcuFitUploader();

  final FitPlatformUploader _stravaUploader;
  final FitPlatformUploader _xingzheUploader;
  final FitPlatformUploader _intervalsIcuUploader;

  FitUploadPlan resolveUploadPlan(Map<String, String> settings) {
    final List<FitUploadPlatform> targets = <FitUploadPlatform>[];

    if (_isEnabled(settings, SettingsService.keyUploadToStrava)) {
      targets.add(FitUploadPlatform.strava);
    }

    if (_isEnabled(settings, SettingsService.keyUploadToXingzhe)) {
      targets.add(FitUploadPlatform.xingzhe);
    }

    if (_isEnabled(settings, SettingsService.keyUploadToIntervalsIcu)) {
      targets.add(FitUploadPlatform.intervalsIcu);
    }

    return FitUploadPlan(
      targets: targets,
      hasMissingConfiguration:
          targets.isEmpty || !_hasRequiredConfiguration(targets, settings),
      targetLabel: _targetLabel(targets),
    );
  }

  Future<FitUploadCoordinatorResult> uploadFile(
    File file,
    Map<String, String> settings,
  ) async {
    final FitUploadPlan plan = resolveUploadPlan(settings);
    if (plan.hasMissingConfiguration) {
      return FitUploadCoordinatorResult(
        status: FitUploadCoordinatorStatus.missingConfiguration,
        platformResults: <FitUploadPlatformResult>[],
      );
    }

    final List<FitUploadPlatformResult> platformResults =
        <FitUploadPlatformResult>[];

    for (final FitUploadPlatform platform in plan.targets) {
      platformResults.add(await _uploadToPlatform(platform, file, settings));
    }

    return FitUploadCoordinatorResult(
      status: _resolveAggregateStatus(platformResults),
      platformResults: platformResults,
    );
  }

  FitUploadCoordinatorStatus _resolveAggregateStatus(
    List<FitUploadPlatformResult> platformResults,
  ) {
    final bool hasSuccessfulUpload = platformResults.any(
      (FitUploadPlatformResult result) =>
          result.status == FitUploadPlatformStatus.success ||
          result.status == FitUploadPlatformStatus.alreadyUploaded,
    );
    if (!hasSuccessfulUpload) {
      return FitUploadCoordinatorStatus.failure;
    }

    final bool hasFailure = platformResults.any(
      (FitUploadPlatformResult result) =>
          result.status == FitUploadPlatformStatus.failure,
    );
    if (hasFailure) {
      return FitUploadCoordinatorStatus.partialSuccess;
    }

    return FitUploadCoordinatorStatus.success;
  }

  Future<FitUploadPlatformResult> _uploadToPlatform(
    FitUploadPlatform platform,
    File file,
    Map<String, String> settings,
  ) async {
    final FitPlatformUploader uploader = switch (platform) {
      FitUploadPlatform.strava => _stravaUploader,
      FitUploadPlatform.xingzhe => _xingzheUploader,
      FitUploadPlatform.intervalsIcu => _intervalsIcuUploader,
    };

    try {
      return await uploader.upload(file: file, settings: settings);
    } on Exception catch (error) {
      return FitUploadPlatformResult(
        platform: platform,
        status: FitUploadPlatformStatus.failure,
        message: error.toString(),
      );
    }
  }

  bool _hasRequiredConfiguration(
    List<FitUploadPlatform> targets,
    Map<String, String> settings,
  ) {
    for (final FitUploadPlatform platform in targets) {
      if (platform == FitUploadPlatform.strava) {
        final bool isWebMode =
            (settings[SettingsService.keyStravaUploadMode] ?? '')
                .trim()
                .toLowerCase() ==
            'web';
        if (isWebMode) {
          if (!_hasValue(settings, SettingsService.keyStravaWebCookies)) {
            return false;
          }
        } else {
          if (!_hasValue(settings, SettingsService.keyStravaClientId) ||
              !_hasValue(settings, SettingsService.keyStravaClientSecret) ||
              !_hasValue(settings, SettingsService.keyStravaRefreshToken)) {
            return false;
          }
        }
      }

      if (platform == FitUploadPlatform.xingzhe &&
          (!_hasValue(settings, SettingsService.keyXingzheUsername) ||
              !_hasValue(settings, SettingsService.keyXingzhePassword))) {
        return false;
      }

      if (platform == FitUploadPlatform.intervalsIcu &&
          (!_hasValue(settings, SettingsService.keyIntervalsIcuAthleteId) ||
              !_hasValue(settings, SettingsService.keyIntervalsIcuApiKey))) {
        return false;
      }
    }

    return true;
  }

  bool _isEnabled(Map<String, String> settings, String key) {
    return (settings[key] ?? '').trim().toLowerCase() == 'true';
  }

  bool _hasValue(Map<String, String> settings, String key) {
    return (settings[key] ?? '').trim().isNotEmpty;
  }

  String _targetLabel(List<FitUploadPlatform> targets) {
    if (targets.length == 3) {
      return 'Strava、行者 和 Intervals.icu';
    }

    if (targets.length == 2) {
      if (targets.contains(FitUploadPlatform.strava) &&
          targets.contains(FitUploadPlatform.xingzhe)) {
        return 'Strava 和行者';
      }
      if (targets.contains(FitUploadPlatform.strava) &&
          targets.contains(FitUploadPlatform.intervalsIcu)) {
        return 'Strava 和 Intervals.icu';
      }
      if (targets.contains(FitUploadPlatform.xingzhe) &&
          targets.contains(FitUploadPlatform.intervalsIcu)) {
        return '行者 和 Intervals.icu';
      }
    }

    if (targets.length == 1) {
      if (targets.contains(FitUploadPlatform.strava)) {
        return 'Strava';
      }
      if (targets.contains(FitUploadPlatform.xingzhe)) {
        return '行者';
      }
      if (targets.contains(FitUploadPlatform.intervalsIcu)) {
        return 'Intervals.icu';
      }
    }

    return '';
  }
}
