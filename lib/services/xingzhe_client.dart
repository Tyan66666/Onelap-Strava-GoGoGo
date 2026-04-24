import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'settings_service.dart';
import 'package:encrypt/encrypt.dart';
import 'package:http_parser/http_parser.dart';

class XingzheRetriableError implements Exception {
  final String message;
  const XingzheRetriableError(this.message);
  @override
  String toString() => 'XingzheRetriableError: $message';
}

class XingzhePermanentError implements Exception {
  final String message;
  const XingzhePermanentError(this.message);
  @override
  String toString() => 'XingzhePermanentError: $message';
}

class XingzheClient {
  String username;
  String password;
  String? authToken;
  final Dio _dio;

  XingzheClient({
    required this.username,
    required this.password,
    this.authToken,
    Dio? dio,
    String? sessionId,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 30),
               headers: {
                 'User-Agent':
                     'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
                 'Accept-Encoding': 'gzip, deflate',
               },
             ),
           ) {
    if (sessionId != null && sessionId.isNotEmpty) {
      _dio.options.headers['Cookie'] =
          'sessionid=$sessionId; _XingzheWeb_Token=true';
    }
  }

  static Future<XingzheClient> create({
    required String username,
    required String password,
    Dio? dio,
  }) async {
    final settingsService = SettingsService();
    final settings = await settingsService.loadSettings();
    final sessionId = settings[SettingsService.keyXingzheSessionId];

    return XingzheClient(
      username: username,
      password: password,
      dio: dio,
      sessionId: sessionId,
    );
  }

  static const String publicKey = '''-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDmuQkBbijudDAJgfffDeeIButq
WHZvUwcRuvWdg89393FSdz3IJUHc0rgI/S3WuU8N0VePJLmVAZtCOK4qe4FY/eKm
WpJmn7JfXB4HTMWjPVoyRZmSYjW4L8GrWmh51Qj7DwpTADadF3aq04o+s1b8LXJa
8r6+TIqqL5WUHtRqmQIDAQAB
-----END PUBLIC KEY-----
''';

  static String _statusSummary(
    int? statusCode, {
    String fallback = 'request failed',
  }) {
    if (statusCode == null) {
      return fallback;
    }
    return '$fallback: HTTP $statusCode';
  }

  static String _sanitizeDetail(Object? detail, {required String fallback}) {
    if (detail == null) {
      return fallback;
    }

    final raw = '$detail'.trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') {
      return fallback;
    }

    var sanitized = raw;
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'([\w.+-]+@[\w.-]+)'),
      (_) => '[redacted-email]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'sessionid=[^\s,;]+', caseSensitive: false),
      (_) => 'sessionid=[redacted]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'password=[^\s,;]+', caseSensitive: false),
      (_) => 'password=[redacted]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'authorization=.*?(?=\s+\w+=|$)', caseSensitive: false),
      (_) => 'authorization=[redacted]',
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'encrypted_password=[^\s,;]+', caseSensitive: false),
      (_) => 'encrypted_password=[redacted]',
    );

    return sanitized.isEmpty ? fallback : sanitized;
  }

  static String _statusWithDetail(
    int? statusCode,
    Object? detail, {
    required String fallback,
  }) {
    final summary = _statusSummary(statusCode, fallback: fallback);
    final sanitized = _sanitizeDetail(detail, fallback: fallback);
    if (sanitized == fallback) {
      return summary;
    }
    return '$summary: $sanitized';
  }

  static String encryptPassword(String password) {
    final parser = RSAKeyParser();
    final rsaPublicKey = parser.parse(publicKey) as RSAPublicKey;

    // 使用 PKCS1_v1_5 加密模式，与 Python 版本一致
    final cipher = PKCS1Encoding(RSAEngine());
    cipher.init(true, PublicKeyParameter<RSAPublicKey>(rsaPublicKey));

    final passwordBytes = utf8.encode(password);
    final encryptedBytes = cipher.process(passwordBytes);
    return base64.encode(encryptedBytes);
  }

  static Future<XingzheClient> login({
    required String username,
    required String password,
    Dio? dio,
  }) async {
    final dioInstance =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36',
              'Accept-Encoding': 'gzip, deflate',
              'Content-Type': 'application/json',
            },
          ),
        );

    final encryptedPassword = encryptPassword(password);
    Response response;
    try {
      response = await dioInstance.post(
        'https://www.imxingzhe.com/api/v1/user/login/',
        data: {'account': username, 'password': encryptedPassword},
        options: Options(contentType: 'application/json'),
      );
    } on DioException catch (e) {
      throw XingzhePermanentError(
        _statusSummary(e.response?.statusCode, fallback: '行者登录失败'),
      );
    }

    if (response.statusCode != 200) {
      throw XingzhePermanentError('行者登录失败: ${response.statusCode}');
    }

    final payload = response.data as Map<String, dynamic>;
    if (payload['data'] == null) {
      throw const XingzhePermanentError('行者登录失败');
    }

    // 从响应头中提取 cookies
    final setCookie = response.headers['set-cookie'];
    final String extractedSessionId = setCookie != null
        ? _extractSessionId(setCookie)
        : '';

    if (extractedSessionId.isNotEmpty) {
      dioInstance.options.headers['Cookie'] =
          'sessionid=$extractedSessionId; _XingzheWeb_Token=true';
      final settingsService = SettingsService();
      await settingsService.saveSettings({
        SettingsService.keyXingzheSessionId: extractedSessionId,
        SettingsService.keyXingzheUsername: username,
        SettingsService.keyXingzhePassword: password,
      });
    }

    return XingzheClient(
      username: username,
      password: password,
      authToken: null,
      dio: dioInstance,
      sessionId: extractedSessionId.isNotEmpty ? extractedSessionId : null,
    );
  }

  /// 从 Set-Cookie header 列表中提取 sessionid
  static String _extractSessionId(List<String> setCookies) {
    for (final cookie in setCookies) {
      final match = RegExp(r'sessionid=([^;]+)').firstMatch(cookie);
      if (match != null) {
        return match.group(1)!;
      }
    }
    return '';
  }

  Future<void> ensureAuthenticated() async {
    // 依赖 session 保持认证状态。
  }

  Future<int> uploadFit(File file, {int retries = 3}) async {
    final String filename = file.path.split('/').last;

    for (var attempt = 1; attempt <= retries; attempt++) {
      Response response;
      try {
        // 计算文件的 MD5 哈希值
        final fileBytes = await file.readAsBytes();
        final md5Hash = md5.convert(fileBytes).toString();

        // 构建 FormData
        final formData = FormData.fromMap({
          'file_source': 'undefined',
          'fit_filename': filename,
          'md5': md5Hash,
          'name': filename,
          'sport': '3',
          'fit_file': await MultipartFile.fromFile(
            file.path,
            filename: filename,
            contentType: MediaType('application', 'octet-stream'),
          ),
        });

        // 发送上传请求
        response = await _dio.post(
          'https://www.imxingzhe.com/api/v1/fit/upload/',
          data: formData,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => true,
          ),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status >= 500 && attempt < retries) {
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        if (status >= 500) {
          throw XingzheRetriableError('xingzhe upload 5xx: $status');
        }
        if (status >= 400) {
          throw XingzhePermanentError(
            _statusWithDetail(
              status,
              e.response?.data is Map<String, dynamic>
                  ? (e.response?.data as Map<String, dynamic>)['msg']
                  : e.response?.data,
              fallback: 'xingzhe upload failed',
            ),
          );
        }
        rethrow;
      } catch (e) {
        rethrow;
      }

      try {
        if (response.statusCode == 500) {
          // 重新登录
          await login(username: username, password: password, dio: _dio);
          if (attempt < retries) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          throw XingzheRetriableError(
            'xingzhe upload 5xx: ${response.statusCode}',
          );
        }

        final payload = response.data as Map<String, dynamic>;

        // 9006 = 文件已上传（幂等成功），从 msg 中提取已存在的 activity_id
        if (payload['code'] == 9006) {
          final msg = '${payload['msg'] ?? ''}';
          final match = RegExp(r'(\d{4,})').firstMatch(msg);
          final existingId = match != null
              ? int.tryParse(match.group(1)!) ?? 0
              : 0;
          return existingId;
        }

        if (response.statusCode != null && response.statusCode! >= 400) {
          throw XingzhePermanentError(
            _statusWithDetail(
              response.statusCode,
              payload['msg'],
              fallback: 'xingzhe upload failed',
            ),
          );
        }

        if (payload['code'] != 0) {
          throw XingzhePermanentError(
            _sanitizeDetail(payload['msg'], fallback: 'xingzhe upload failed'),
          );
        }

        // 行者上传成功后返回 workout_id，即真实活动 ID
        final data = payload['data'] as Map<String, dynamic>?;
        final workoutIdRaw = data?['workout_id'] ?? data?['id'];
        if (workoutIdRaw == null) {
          return 0;
        }
        final int workoutId = workoutIdRaw is int
            ? workoutIdRaw
            : int.tryParse('$workoutIdRaw') ?? 0;
        return workoutId;
      } catch (e) {
        rethrow;
      }
    }
    throw XingzheRetriableError('xingzhe upload exhausted retries');
  }

  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) async {
    // 行者上传接口是同步的，uploadFit 返回的 workout_id 就是真实活动 ID
    // pollUpload 在这里只做兜底：如果 uploadId 为 0（之前没拿到 workout_id），
    // 尝试通过 MD5 查一下已上传的活动。
    if (uploadId > 0) {
      return {'status': 'complete', 'activity_id': uploadId};
    }

    // 兜底查询（uploadId=0 时才走到这里）
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final resp = await _dio.get(
          'https://www.imxingzhe.com/api/v1/fit/list/',
        );
        final payload = resp.data as Map<String, dynamic>;
        if (payload['code'] == 0) {
          final List<dynamic> items = payload['data'] as List<dynamic>? ?? [];
          if (items.isNotEmpty) {
            final latest = items.first as Map<String, dynamic>;
            final id = latest['id'] ?? latest['workout_id'];
            return {'status': 'complete', 'activity_id': id};
          }
        }
      } catch (_) {
        // Ignore fallback lookup failures and keep polling.
      }
      if (attempt < maxAttempts - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    return {'status': 'unknown', 'activity_id': null};
  }
}
