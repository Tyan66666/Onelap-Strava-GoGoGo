import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'strava_client.dart' show StravaRetriableError;

class StravaWebSessionExpiredError implements Exception {
  final String message;
  const StravaWebSessionExpiredError([this.message = 'Strava 网页登录已过期']);
  @override
  String toString() => 'StravaWebSessionExpiredError: $message';
}

class StravaWebUploadError implements Exception {
  final String message;
  const StravaWebUploadError(this.message);
  @override
  String toString() => 'StravaWebUploadError: $message';
}

class StravaWebClient {
  static const _uploadUrl = 'https://www.strava.com/upload/files';
  static const _progressUrl = 'https://www.strava.com/upload/progress.json';
  static const _selectUrl = 'https://www.strava.com/upload/select';

  final Dio _dio;

  StravaWebClient({required String cookies, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Cookie': cookies},
            ),
          );

  Future<String> _fetchCsrfToken() async {
    try {
      final response = await _dio.get<String>(_selectUrl);
      final html = response.data ?? '';
      final match = RegExp(
        r'<meta\s+name="csrf-token"\s+content="([^"]+)"',
      ).firstMatch(html);
      if (match == null) {
        throw const StravaWebUploadError('CSRF token not found');
      }
      return match.group(1)!;
    } on DioException catch (e) {
      throw StravaWebUploadError(
        'CSRF fetch failed (${e.response?.statusCode}): ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<bool> isSessionValid() async {
    try {
      final response = await _dio.get(
        _selectUrl,
        options: Options(followRedirects: false),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  List<dynamic> _parseJsonList(dynamic data) {
    if (data is List) return data;
    if (data is String) return jsonDecode(data) as List<dynamic>;
    throw StravaWebUploadError('Unexpected response type: ${data.runtimeType}');
  }

  Future<Map<String, dynamic>> uploadFit(File file) async {
    final csrfToken = await _fetchCsrfToken();
    try {
      final response = await _dio.post(
        _uploadUrl,
        data: FormData.fromMap({
          'files[]': await MultipartFile.fromFile(
            file.path,
            filename: file.path.split('/').last,
          ),
          '_method': 'POST',
          'authenticity_token': csrfToken,
        }),
      );
      final payload =
          _parseJsonList(response.data).first as Map<String, dynamic>;
      return {
        'upload_id': payload['id'],
        'workflow': payload['workflow'] ?? 'pending',
      };
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 429) {
        throw const StravaRetriableError('strava web upload rate limited');
      }
      if (status == 403) {
        throw const StravaWebSessionExpiredError();
      }
      throw StravaWebUploadError(
        'Upload failed ($status): ${e.response?.data ?? e.message}',
      );
    }
  }

  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _dio.get(
          _progressUrl,
          queryParameters: {'ids[]': uploadId},
        );
        final payload =
            _parseJsonList(response.data).first as Map<String, dynamic>;
        final workflow = payload['workflow'] as String? ?? '';
        _lastPollWorkflow = workflow;
        if (workflow == 'complete' ||
            workflow == 'done' ||
            workflow == 'success') {
          return {
            'activity_id': payload['activity_id'] ?? payload['id'],
            'workflow': 'complete',
          };
        }
        if (workflow == 'error') {
          return {
            'error': payload['error'] ?? 'Unknown error',
            'workflow': 'error',
          };
        }
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status == 429) {
          throw const StravaRetriableError('strava web poll rate limited');
        }
        throw StravaWebUploadError(
          'Poll failed ($status): ${e.response?.data ?? e.message}',
        );
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return {
      'error': 'poll timeout (last workflow: $_lastPollWorkflow)',
      'workflow': 'error',
    };
  }

  String _lastPollWorkflow = 'unknown';
}
