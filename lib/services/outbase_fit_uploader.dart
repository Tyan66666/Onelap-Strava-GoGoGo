import 'dart:io';

import 'fit_upload_coordinator.dart';
import 'outbase_client.dart';
import 'settings_service.dart';

class OutbaseFitUploader implements FitPlatformUploader {
  OutbaseFitUploader({OutbaseClient? client}) : _client = client;

  final OutbaseClient? _client;

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    final sessionId = settings[SettingsService.keyOutbaseSessionId] ?? '';

    if (sessionId.isEmpty) {
      return const FitUploadPlatformResult(
        platform: FitUploadPlatform.outbase,
        status: FitUploadPlatformStatus.failure,
        message: 'Outbase 未登录，请先在设置中登录',
      );
    }

    final client = _client ?? OutbaseClient(sessionId: sessionId);
    try {
      final result = await client.uploadFit(file);
      if (result.success) {
        return const FitUploadPlatformResult(
          platform: FitUploadPlatform.outbase,
          status: FitUploadPlatformStatus.success,
        );
      }
      if (result.alreadyUploaded) {
        return const FitUploadPlatformResult(
          platform: FitUploadPlatform.outbase,
          status: FitUploadPlatformStatus.alreadyUploaded,
        );
      }
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.outbase,
        status: FitUploadPlatformStatus.failure,
        message: result.message ?? 'Outbase upload failed',
      );
    } on OutbasePermanentError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.outbase,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    } on OutbaseRetriableError catch (e) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.outbase,
        status: FitUploadPlatformStatus.failure,
        message: e.message,
      );
    }
  }
}
