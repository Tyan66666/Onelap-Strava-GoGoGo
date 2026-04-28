import 'dart:io';

import '../models/shared_fit_draft.dart';
import 'fit_coordinate_rewrite_service.dart';
import 'fit_upload_coordinator.dart';
import 'settings_service.dart';

enum SharedFitUploadStatus {
  missingConfiguration,
  invalidFile,
  success,
  failure,
}

class SharedFitUploadResult {
  final SharedFitUploadStatus status;
  final String? message;

  const SharedFitUploadResult({required this.status, this.message});
}

typedef SharedFitSettingsLoader = Future<Map<String, String>> Function();

class SharedFitUploadService {
  SharedFitUploadService({
    SharedFitSettingsLoader? loadSettings,
    FitCoordinateRewriteService? rewriteService,
    FitUploadCoordinator? coordinator,
  }) : _loadSettings = loadSettings ?? SettingsService().loadSettings,
       _rewriteService = rewriteService,
       _coordinator = coordinator ?? FitUploadCoordinator();

  final SharedFitSettingsLoader _loadSettings;
  final FitCoordinateRewriteService? _rewriteService;
  final FitUploadCoordinator _coordinator;

  Future<FitUploadPlan> loadUploadPlan() async {
    final Map<String, String> settings = await _loadSettings();
    return _coordinator.resolveUploadPlan(settings);
  }

  Future<SharedFitUploadResult> uploadDraft(SharedFitDraft draft) async {
    if (!_hasFitExtension(draft)) {
      return const SharedFitUploadResult(
        status: SharedFitUploadStatus.invalidFile,
      );
    }

    final File file = File(draft.localFilePath);
    if (!await _isReadableFile(file)) {
      return const SharedFitUploadResult(
        status: SharedFitUploadStatus.invalidFile,
      );
    }

    final Map<String, String> settings;
    try {
      settings = await _loadSettings();
    } on Exception catch (error) {
      return SharedFitUploadResult(
        status: SharedFitUploadStatus.failure,
        message:
            'Failed to load settings: ${'$error'.replaceFirst('Exception: ', '')}',
      );
    }

    final FitUploadPlan plan = _coordinator.resolveUploadPlan(settings);
    if (plan.hasMissingConfiguration) {
      return const SharedFitUploadResult(
        status: SharedFitUploadStatus.missingConfiguration,
      );
    }

    File uploadFile = file;
    bool shouldDeleteUploadFile = false;
    if (_isGcjCorrectionEnabled(settings)) {
      final FitCoordinateRewriteService rewriteService =
          _rewriteService ?? FitCoordinateRewriteService();
      try {
        uploadFile = await rewriteService.rewrite(file);
        shouldDeleteUploadFile = uploadFile.path != file.path;
      } on Exception catch (error) {
        return SharedFitUploadResult(
          status: SharedFitUploadStatus.failure,
          message:
              'FIT coordinate rewrite failed: ${'$error'.replaceFirst('Exception: ', '')}',
        );
      }
    }

    try {
      final FitUploadCoordinatorResult coordinatorResult = await _coordinator
          .uploadFile(uploadFile, settings);
      return _mapCoordinatorResult(coordinatorResult);
    } on Exception catch (error) {
      return SharedFitUploadResult(
        status: SharedFitUploadStatus.failure,
        message: '$error'.replaceFirst('Exception: ', ''),
      );
    } finally {
      if (shouldDeleteUploadFile) {
        await _deleteTempUploadFile(uploadFile);
      }
    }
  }

  bool _hasFitExtension(SharedFitDraft draft) {
    return draft.localFilePath.toLowerCase().endsWith('.fit') ||
        draft.displayName.toLowerCase().endsWith('.fit');
  }

  bool _isGcjCorrectionEnabled(Map<String, String> settings) {
    return (settings[SettingsService.keyGcjCorrectionEnabled] ?? '')
            .trim()
            .toLowerCase() ==
        'true';
  }

  Future<bool> _isReadableFile(File file) async {
    if (!await file.exists()) {
      return false;
    }

    try {
      await file.length();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _deleteTempUploadFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup for rewritten temp files.
    }
  }

  SharedFitUploadResult _mapCoordinatorResult(
    FitUploadCoordinatorResult coordinatorResult,
  ) {
    switch (coordinatorResult.status) {
      case FitUploadCoordinatorStatus.missingConfiguration:
        return const SharedFitUploadResult(
          status: SharedFitUploadStatus.missingConfiguration,
        );
      case FitUploadCoordinatorStatus.success:
        return SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: _buildSuccessMessage(coordinatorResult.platformResults),
        );
      case FitUploadCoordinatorStatus.partialSuccess:
        return SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: _buildPartialSuccessMessage(
            coordinatorResult.platformResults,
          ),
        );
      case FitUploadCoordinatorStatus.failure:
        return SharedFitUploadResult(
          status: SharedFitUploadStatus.failure,
          message: _buildFailureMessage(coordinatorResult.platformResults),
        );
    }
  }

  String? _buildSuccessMessage(List<FitUploadPlatformResult> platformResults) {
    final List<String> successfulTargets = _successfulTargetLabels(
      platformResults,
    );
    if (successfulTargets.isEmpty) {
      return null;
    }

    return 'FIT 文件已经上传到 ${_joinTargetLabels(successfulTargets)}。';
  }

  String? _buildPartialSuccessMessage(
    List<FitUploadPlatformResult> platformResults,
  ) {
    final List<String> successfulTargets = _successfulTargetLabels(
      platformResults,
    );
    final List<String> failureMessages = platformResults
        .where(
          (FitUploadPlatformResult result) =>
              result.status == FitUploadPlatformStatus.failure,
        )
        .map(
          (FitUploadPlatformResult result) =>
              '${_platformLabel(result.platform)}上传失败${_formatFailureDetail(result.message)}',
        )
        .toList();

    if (successfulTargets.isEmpty) {
      return _buildFailureMessage(platformResults);
    }

    if (failureMessages.isEmpty) {
      return 'FIT 文件已经上传到 ${_joinTargetLabels(successfulTargets)}。';
    }

    return '已上传到 ${_joinTargetLabels(successfulTargets)}；${failureMessages.join('；')}';
  }

  String? _buildFailureMessage(List<FitUploadPlatformResult> platformResults) {
    final List<String> failureMessages = platformResults
        .where(
          (FitUploadPlatformResult result) =>
              result.status == FitUploadPlatformStatus.failure,
        )
        .map(
          (FitUploadPlatformResult result) =>
              '${_platformLabel(result.platform)}上传失败${_formatFailureDetail(result.message)}',
        )
        .toList();

    if (failureMessages.isNotEmpty) {
      return failureMessages.join('；');
    }

    return null;
  }

  List<String> _successfulTargetLabels(
    List<FitUploadPlatformResult> platformResults,
  ) {
    return platformResults
        .where(
          (FitUploadPlatformResult result) =>
              result.status == FitUploadPlatformStatus.success ||
              result.status == FitUploadPlatformStatus.alreadyUploaded,
        )
        .map(
          (FitUploadPlatformResult result) => _platformLabel(result.platform),
        )
        .toList();
  }

  String _joinTargetLabels(List<String> labels) {
    if (labels.length == 2) {
      return '${labels.first} 和${labels.last}';
    }

    return labels.join('、');
  }

  String _platformLabel(FitUploadPlatform platform) {
    return switch (platform) {
      FitUploadPlatform.strava => 'Strava',
      FitUploadPlatform.xingzhe => '行者',
    };
  }

  String _formatFailureDetail(String? message) {
    final String trimmedMessage = (message ?? '').trim();
    if (trimmedMessage.isEmpty) {
      return '';
    }

    return '：$trimmedMessage';
  }
}
