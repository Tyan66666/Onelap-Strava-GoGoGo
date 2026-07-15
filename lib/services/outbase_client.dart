import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class OutbaseUploadResult {
  final bool success;
  final bool alreadyUploaded;
  final String? message;

  const OutbaseUploadResult({
    required this.success,
    required this.alreadyUploaded,
    this.message,
  });
}

class OutbasePermanentError implements Exception {
  final String message;
  const OutbasePermanentError(this.message);
  @override
  String toString() => 'OutbasePermanentError: $message';
}

class OutbaseRetriableError implements Exception {
  final String message;
  const OutbaseRetriableError(this.message);
  @override
  String toString() => 'OutbaseRetriableError: $message';
}

class OutbaseClient {
  final String sessionId;
  final Dio _dio;

  OutbaseClient({required this.sessionId, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  Future<OutbaseUploadResult> uploadFit(File file) async {
    final fileBytes = await file.readAsBytes();
    final guid = _generateGuid();
    final dateTag = _dateTag();

    // Step 1: CDN upload
    final cdnUrl = _buildCdnUrl(guid, dateTag);
    if (kDebugMode) debugPrint('Outbase CDN URL: $cdnUrl');
    bool cdnFileAlreadyExists = false;
    try {
      final cdnResponse = await _dio.post(
        cdnUrl,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            fileBytes,
            filename: file.path.split('/').last,
          ),
        }),
      );
      final cdnStatus = cdnResponse.statusCode ?? 0;
      final cdnData = cdnResponse.data;
      if (cdnStatus >= 400) {
        // CDN 400 may indicate the file already exists — check response body
        final body = cdnData is Map<String, dynamic>
            ? (cdnData['message'] as String? ?? '')
            : cdnData.toString();
        if (_isDuplicateIndication(body)) {
          cdnFileAlreadyExists = true;
        } else {
          throw OutbasePermanentError(
            'CDN upload failed: $cdnStatus $body',
          );
        }
      }
      if (!cdnFileAlreadyExists) {
        if (cdnData is Map<String, dynamic>) {
          final message = cdnData['message'] as String?;
          if (message != 'SUCCESS') {
            throw OutbasePermanentError(
              'CDN upload unexpected response: $message',
            );
          }
        } else {
          throw const OutbasePermanentError('Unexpected CDN response format');
        }
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status >= 400 && status < 500) {
        // Check if 4xx indicates duplicate
        final body = e.response?.data;
        final bodyStr = body is Map<String, dynamic>
            ? (body['message'] as String? ?? '')
            : body.toString();
        if (_isDuplicateIndication(bodyStr)) {
          cdnFileAlreadyExists = true;
        } else {
          throw OutbasePermanentError('CDN upload failed: $status');
        }
      } else {
        throw OutbaseRetriableError('CDN upload network error: ${e.message}');
      }
    }

    // Step 2: API registration
    // API 使用 sessionid + uagent 自定义 header 认证（通过浏览器抓包确认）
    // uagent 必须包含 "PCAgent/1.0.0"，否则服务器返回 "Please log in"
    final sign = md5.convert(fileBytes).toString();
    final fileName = file.path.split('/').last;
    final fitGuid = guid;
    try {
      final apiResponse = await _dio.post(
        'https://melon-gateway.immomo.com/zeusfit/api/h5/sport/upload/fit',
        options: Options(
          headers: {
            'sessionid': sessionId,
            'uagent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36 Edg/150.0.0.0 PCAgent/1.0.0',
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
        data: {
          'fitGuid': fitGuid,
          'sign': sign,
          'fileName': fileName,
          'fileSize': fileBytes.length,
        },
      );

      final apiStatus = apiResponse.statusCode ?? 0;
      if (apiStatus == 401) {
        throw const OutbasePermanentError(
          'Outbase session expired, please re-login',
        );
      }
      if (apiStatus >= 400) {
        throw OutbasePermanentError('API registration failed: $apiStatus');
      }

      final apiData = apiResponse.data;
      if (apiData is Map<String, dynamic>) {
        final ec = apiData['ec'];
        if (ec == 0) {
          return const OutbaseUploadResult(
            success: true,
            alreadyUploaded: false,
          );
        }
        final em = apiData['em'] as String? ?? '';
        // ec: 503 或消息包含"已存在"/"相同时间" → 视为已上传
        if (ec == 503 ||
            em.contains('相同时间内已存在其他运动数据') ||
            em.contains('已存在') ||
            em.contains('请勿重复上传')) {
          return OutbaseUploadResult(
            success: false,
            alreadyUploaded: true,
            message: em,
          );
        }
        // session 过期或未登录
        if (em.toLowerCase().contains('log in') ||
            em.contains('登录') ||
            em.contains('session')) {
          throw OutbasePermanentError('Outbase 未登录或 session 已过期: $em');
        }
        return OutbaseUploadResult(
          success: false,
          alreadyUploaded: false,
          message: em,
        );
      }
      return const OutbaseUploadResult(
        success: false,
        alreadyUploaded: false,
        message: 'Unexpected API response',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        throw const OutbasePermanentError(
          'Outbase session expired, please re-login',
        );
      }
      if (status >= 400 && status < 500) {
        throw OutbasePermanentError('API registration failed: $status');
      }
      throw OutbaseRetriableError(
        'API registration network error: ${e.message}',
      );
    } on OutbasePermanentError {
      rethrow;
    }
  }

  String _generateGuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  String _dateTag() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// 构建 CDN 上传 URL。
  ///
  /// 格式（通过 agent-browser 抓取浏览器真实请求确认）：
  /// - `id`: guid（带连字符）+ dateTag，如 `a789001e-17da-4b70-a824-ebf89031d6c220260714`
  /// - `uri`: 前缀用 hex-only 前 4 字符，文件名用 guid+dateTag
  ///   如 `/resource/a7/89/a789001e-17da-4b70-a824-ebf89031d6c220260714.fit`
  /// - `uri` 中文件名必须包含 dateTag，否则 CDN 返回 "meta.uri is illegal"
  String _buildCdnUrl(String guid, String dateTag) {
    final guidHex = guid.replaceAll('-', '');
    final prefix1 = guidHex.substring(0, 2);
    final prefix2 = guidHex.substring(2, 4);
    return 'https://melon-gateway.immomo.com/zeusfit/resource/upload'
        '?source=zeusfit'
        '&id=$guid$dateTag'
        '&uri=/resource/$prefix1/$prefix2/$guid$dateTag.fit'
        '&momoid=0&';
  }

  bool _isDuplicateIndication(String message) {
    final lower = message.toLowerCase();
    return lower.contains('already') ||
        lower.contains('exist') ||
        lower.contains('duplicate') ||
        lower.contains('已存在') ||
        lower.contains('已上传');
  }
}
