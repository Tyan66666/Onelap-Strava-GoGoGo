import 'dart:io';

import 'fit_upload_coordinator.dart';
import 'settings_service.dart';
import 'xingzhe_client.dart';

class XingzheFitUploadResponse {
  const XingzheFitUploadResponse({
    required this.uploadId,
    this.alreadyUploaded = false,
    this.message,
    this.remoteActivityId,
  });

  final int uploadId;
  final bool alreadyUploaded;
  final String? message;
  final int? remoteActivityId;
}

typedef XingzheDetailedUploadInvoker =
    Future<XingzheUploadFitResult> Function(File file);

abstract class XingzheFitUploadClient {
  Future<XingzheFitUploadResponse> uploadFit(File file);

  Future<Map<String, dynamic>> pollUpload(int uploadId);
}

typedef XingzheSessionClientFactory =
    Future<XingzheFitUploadClient> Function({
      required String username,
      required String password,
      required String sessionId,
    });

typedef XingzheLoginClientFactory =
    Future<XingzheFitUploadClient> Function({
      required String username,
      required String password,
    });

class XingzheFitUploader implements FitPlatformUploader {
  XingzheFitUploader({
    XingzheSessionClientFactory? createClientWithSession,
    XingzheLoginClientFactory? loginClient,
  }) : _createClientWithSession =
           createClientWithSession ?? _defaultSessionClientFactory,
       _loginClient = loginClient ?? _defaultLoginClientFactory;

  final XingzheSessionClientFactory _createClientWithSession;
  final XingzheLoginClientFactory _loginClient;

  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    final String username = settings[SettingsService.keyXingzheUsername] ?? '';
    final String password = settings[SettingsService.keyXingzhePassword] ?? '';
    final String sessionId =
        settings[SettingsService.keyXingzheSessionId] ?? '';

    final XingzheFitUploadClient client = sessionId.trim().isNotEmpty
        ? await _createClientWithSession(
            username: username,
            password: password,
            sessionId: sessionId,
          )
        : await _loginClient(username: username, password: password);

    final XingzheFitUploadResponse uploadResponse = await client.uploadFit(
      file,
    );
    final String uploadMessage = uploadResponse.message ?? '';
    final int? uploadRemoteActivityId = uploadResponse.remoteActivityId;
    final bool hasExistingActivityId =
        uploadRemoteActivityId != null && uploadResponse.uploadId == 0;
    if (uploadResponse.alreadyUploaded ||
        _isIdempotentMessage(uploadMessage) ||
        hasExistingActivityId) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.xingzhe,
        status: FitUploadPlatformStatus.alreadyUploaded,
        message: uploadMessage,
        remoteActivityId: uploadRemoteActivityId,
      );
    }

    final Map<String, dynamic> pollResult = await client.pollUpload(
      uploadResponse.uploadId,
    );
    final Object? activityId = pollResult['activity_id'];
    final String pollMessage =
        '${pollResult['error'] ?? pollResult['status'] ?? ''}';

    if (activityId != null && '$activityId' != '0') {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.xingzhe,
        status: FitUploadPlatformStatus.success,
        remoteActivityId: _parseActivityId(activityId),
      );
    }

    if (_isIdempotentMessage(pollMessage)) {
      return FitUploadPlatformResult(
        platform: FitUploadPlatform.xingzhe,
        status: FitUploadPlatformStatus.alreadyUploaded,
        message: pollMessage,
        remoteActivityId: _parseActivityId(activityId),
      );
    }

    return FitUploadPlatformResult(
      platform: FitUploadPlatform.xingzhe,
      status: FitUploadPlatformStatus.failure,
      message: 'Xingzhe upload incomplete: $pollMessage',
    );
  }

  static Future<XingzheFitUploadClient> _defaultSessionClientFactory({
    required String username,
    required String password,
    required String sessionId,
  }) async {
    return _XingzheFitUploadClientAdapter(
      XingzheClient(
        username: username,
        password: password,
        sessionId: sessionId,
      ),
    );
  }

  static Future<XingzheFitUploadClient> _defaultLoginClientFactory({
    required String username,
    required String password,
  }) async {
    return _XingzheFitUploadClientAdapter(
      await XingzheClient.login(username: username, password: password),
    );
  }

  static bool _isIdempotentMessage(String message) {
    final String normalized = message.toLowerCase();
    return normalized.contains('9006') ||
        normalized.contains('文件已上传') ||
        normalized.contains('already') ||
        normalized.contains('duplicate') ||
        normalized.contains('dedupe') ||
        normalized.contains('already exists') ||
        normalized.contains('duplicate of');
  }

  static int? _parseActivityId(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse('$value');
  }
}

class _XingzheFitUploadClientAdapter implements XingzheFitUploadClient {
  _XingzheFitUploadClientAdapter(this._client);

  final XingzheClient _client;

  @override
  Future<XingzheFitUploadResponse> uploadFit(File file) async {
    try {
      final XingzheUploadFitResult result = await _client.uploadFitDetailed(
        file,
      );
      return XingzheFitUploadResponse(
        uploadId: result.uploadId,
        alreadyUploaded: result.alreadyUploaded,
        message: result.message,
        remoteActivityId: result.remoteActivityId,
      );
    } on Exception catch (error) {
      final String message = error.toString();
      if (XingzheFitUploader._isIdempotentMessage(message)) {
        return XingzheFitUploadResponse(
          uploadId: 0,
          alreadyUploaded: true,
          message: message,
        );
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _client.pollUpload(uploadId);
  }
}

class XingzheFitUploadClientAdapter extends _XingzheFitUploadClientAdapter {
  XingzheFitUploadClientAdapter(super.client);
}
