import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

class IntervalsIcuRetriableError implements Exception {
  final String message;
  const IntervalsIcuRetriableError(this.message);
  @override
  String toString() => 'IntervalsIcuRetriableError: $message';
}

class IntervalsIcuPermanentError implements Exception {
  final String message;
  const IntervalsIcuPermanentError(this.message);
  @override
  String toString() => 'IntervalsIcuPermanentError: $message';
}

class IntervalsIcuClient {
  final String athleteId;
  final String apiKey;
  final Dio _dio;

  IntervalsIcuClient({required this.athleteId, required this.apiKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  Future<int> uploadFit(File file, {int retries = 3}) async {
    for (var attempt = 1; attempt <= retries; attempt++) {
      Response response;
      try {
        response = await _dio.post(
          'https://intervals.icu/api/v1/athlete/$athleteId/activities',
          options: Options(
            headers: {'Authorization': 'Basic ${_basicAuth()}'},
            validateStatus: (status) => status != null && status < 500,
          ),
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(
              file.path,
              filename: file.path.split('/').last,
            ),
          }),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if ((status >= 500 || status == 429) && attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        if (status >= 500 || status == 429) {
          throw IntervalsIcuRetriableError(
            'intervals.icu upload retriable: $status',
          );
        }
        if (status == 401) {
          throw const IntervalsIcuPermanentError('intervals.icu: API Key 无效');
        }
        if (status >= 400) {
          throw IntervalsIcuPermanentError(
            'intervals.icu upload failed: $status',
          );
        }
        rethrow;
      }

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 201 || statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final id = data['id'];
          if (id is int) return id;
          if (id is num) return id.toInt();
          return int.tryParse('$id') ?? 0;
        }
        return 0;
      }

      if (statusCode == 401) {
        throw const IntervalsIcuPermanentError('intervals.icu: API Key 无效');
      }
      if (statusCode == 429 || statusCode >= 500) {
        if (attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        throw IntervalsIcuRetriableError(
          'intervals.icu upload retriable: $statusCode',
        );
      }
      if (statusCode >= 400) {
        throw IntervalsIcuPermanentError(
          'intervals.icu upload failed: $statusCode',
        );
      }
    }
    throw const IntervalsIcuRetriableError(
      'intervals.icu upload exhausted retries',
    );
  }

  String _basicAuth() {
    final bytes = utf8.encode('API_KEY:$apiKey');
    return base64.encode(bytes);
  }
}
