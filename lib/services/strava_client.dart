import 'dart:io';
import 'package:dio/dio.dart';
import 'settings_service.dart';

class StravaRetriableError implements Exception {
  final String message;
  const StravaRetriableError(this.message);
  @override
  String toString() => 'StravaRetriableError: $message';
}

class StravaPermanentError implements Exception {
  final String message;
  const StravaPermanentError(this.message);
  @override
  String toString() => 'StravaPermanentError: $message';
}

class StravaClient {
  final String clientId;
  final String clientSecret;
  String refreshToken;
  String accessToken;
  int expiresAt;
  final Dio _dio;

  final _settingsService = SettingsService();

  StravaClient({
    required this.clientId,
    required this.clientSecret,
    required this.refreshToken,
    required this.accessToken,
    required this.expiresAt,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  Future<String> ensureAccessToken() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (accessToken.isNotEmpty && expiresAt > now) return accessToken;

    final previousAccessToken = accessToken;
    final previousRefreshToken = refreshToken;
    final previousExpiresAt = expiresAt;

    final response = await _dio.post(
      'https://www.strava.com/oauth/token',
      data: FormData.fromMap({
        'client_id': clientId,
        'client_secret': clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      }),
    );
    final payload = response.data as Map<String, dynamic>;
    accessToken = payload['access_token'] as String;
    refreshToken = (payload['refresh_token'] as String?) ?? refreshToken;
    expiresAt = (payload['expires_at'] as int?) ?? expiresAt;

    final tokenStateChanged =
        accessToken != previousAccessToken ||
        refreshToken != previousRefreshToken ||
        expiresAt != previousExpiresAt;

    if (tokenStateChanged) {
      await _settingsService.saveSettings({
        SettingsService.keyStravaAccessToken: accessToken,
        SettingsService.keyStravaRefreshToken: refreshToken,
        SettingsService.keyStravaExpiresAt: '$expiresAt',
      });
    }

    return accessToken;
  }

  Future<int> uploadFit(File file, {int retries = 3}) async {
    final String dataType = _dataTypeForFile(file);

    for (var attempt = 1; attempt <= retries; attempt++) {
      final token = await ensureAccessToken();
      Response response;
      try {
        response = await _dio.post(
          'https://www.strava.com/api/v3/uploads',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
          data: FormData.fromMap({
            'data_type': dataType,
            'file': await MultipartFile.fromFile(
              file.path,
              filename: file.path.split('/').last,
            ),
          }),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status >= 500 && attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        if (status >= 500) {
          throw StravaRetriableError('strava upload 5xx: $status');
        }
        if (status >= 400) {
          String detail;
          try {
            detail = '${e.response?.data}';
          } catch (_) {
            detail = '';
          }
          throw StravaPermanentError(
            'strava upload failed: $status detail=$detail',
          );
        }
        rethrow;
      }
      final payload = response.data as Map<String, dynamic>;
      return payload['id'] as int;
    }
    throw StravaRetriableError('strava upload exhausted retries');
  }

  String _dataTypeForFile(File file) {
    final String path = file.path.toLowerCase();
    if (path.endsWith('.gpx')) return 'gpx';
    return 'fit';
  }

  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) async {
    Map<String, dynamic> last = {
      'status': 'unknown',
      'error': 'poll timeout',
      'activity_id': null,
    };
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final token = await ensureAccessToken();
      Response response;
      try {
        response = await _dio.get(
          'https://www.strava.com/api/v3/uploads/$uploadId',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status >= 500 && attempt < maxAttempts - 1) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        rethrow;
      }
      final payload = response.data as Map<String, dynamic>;
      last = payload;
      if (payload['error'] != null) return payload;
      if (payload['activity_id'] != null) return payload;
      final status = '${payload['status'] ?? ''}'.toLowerCase();
      if (status == 'ready' || status == 'complete') return payload;
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return last;
  }

  Future<bool> activityExists(int activityId) async {
    final token = await ensureAccessToken();
    try {
      final response = await _dio.get(
        'https://www.strava.com/api/v3/activities/$activityId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode == HttpStatus.notFound) return false;
      return true;
    } on DioException catch (_) {
      return true;
    }
  }
}
