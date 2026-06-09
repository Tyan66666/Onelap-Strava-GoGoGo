import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/strava_client.dart'
    show StravaRetriableError;
import 'package:onelap_strava_sync/services/strava_web_client.dart';

class _MockAdapter implements HttpClientAdapter {
  final Map<String, _MockResponse> _responses = {};

  void onGet(String url, _MockResponse response) =>
      _responses['GET $url'] = response;

  void onPost(String url, _MockResponse response) =>
      _responses['POST $url'] = response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.uri}';
    final mock = _responses[key];
    if (mock == null) {
      return ResponseBody.fromString('Not mocked: $key', 404);
    }
    return ResponseBody.fromString(
      mock.body,
      mock.statusCode,
      headers: mock.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MockResponse {
  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;

  _MockResponse(
    this.statusCode,
    this.body, {
    Map<String, List<String>>? headers,
  }) : headers = headers ?? const {};
}

void main() {
  group('StravaWebClient', () {
    late Dio dio;
    late _MockAdapter adapter;
    late File tempFile;

    setUp(() {
      adapter = _MockAdapter();
      dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      dio.httpClientAdapter = adapter;
      tempFile = File('${Directory.systemTemp.path}/test_upload.fit')
        ..writeAsBytesSync([0x0E, 0x20, 0x00, 0x08]);
    });

    tearDown(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    StravaWebClient createClient() =>
        StravaWebClient(cookies: 'session=abc123', dio: dio);

    group('uploadFit', () {
      test('returns upload_id on success', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<meta name="csrf-token" content="csrf-token">'),
        );
        adapter.onPost(
          'https://www.strava.com/upload/files',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 12345, 'workflow': 'new'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.uploadFit(tempFile);
        expect(result['upload_id'], 12345);
        expect(result['workflow'], 'new');
      });

      test('throws StravaRetriableError on 429', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<meta name="csrf-token" content="csrf-token">'),
        );
        adapter.onPost(
          'https://www.strava.com/upload/files',
          _MockResponse(429, 'rate limited'),
        );

        final client = createClient();
        expect(
          () => client.uploadFit(tempFile),
          throwsA(isA<StravaRetriableError>()),
        );
      });

      test('throws StravaWebSessionExpiredError on 403', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<meta name="csrf-token" content="csrf-token">'),
        );
        adapter.onPost(
          'https://www.strava.com/upload/files',
          _MockResponse(403, 'forbidden'),
        );

        final client = createClient();
        expect(
          () => client.uploadFit(tempFile),
          throwsA(isA<StravaWebSessionExpiredError>()),
        );
      });

      test('throws StravaWebUploadError on 400', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<meta name="csrf-token" content="csrf-token">'),
        );
        adapter.onPost(
          'https://www.strava.com/upload/files',
          _MockResponse(400, 'bad request'),
        );

        final client = createClient();
        expect(
          () => client.uploadFit(tempFile),
          throwsA(isA<StravaWebUploadError>()),
        );
      });

      test('throws StravaWebUploadError when CSRF not found', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<html></html>'),
        );

        final client = createClient();
        expect(
          () => client.uploadFit(tempFile),
          throwsA(isA<StravaWebUploadError>()),
        );
      });
    });

    group('pollUpload', () {
      test('returns activity_id on workflow complete', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=111',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 111, 'activity_id': 42, 'workflow': 'complete'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(111, maxAttempts: 1);
        expect(result['activity_id'], 42);
        expect(result['workflow'], 'complete');
      });

      test('returns activity_id on workflow done', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=112',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 112, 'activity_id': 43, 'workflow': 'done'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(112, maxAttempts: 1);
        expect(result['activity_id'], 43);
        expect(result['workflow'], 'complete');
      });

      test('returns activity_id on workflow success', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=113',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 113, 'activity_id': 44, 'workflow': 'success'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(113, maxAttempts: 1);
        expect(result['activity_id'], 44);
        expect(result['workflow'], 'complete');
      });

      test('falls back to id when activity_id is absent', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=114',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 999, 'workflow': 'complete'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(114, maxAttempts: 1);
        expect(result['activity_id'], 999);
      });

      test('returns error on workflow error', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=222',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 222, 'workflow': 'error', 'error': 'malformed file'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(222, maxAttempts: 1);
        expect(result['error'], 'malformed file');
        expect(result['workflow'], 'error');
      });

      test('returns timeout after maxAttempts', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=333',
          _MockResponse(
            200,
            jsonEncode([
              {'id': 333, 'workflow': 'processing'},
            ]),
          ),
        );

        final client = createClient();
        final result = await client.pollUpload(333, maxAttempts: 2);
        expect(result['error'], contains('poll timeout'));
        expect(result['workflow'], 'error');
      });

      test('throws StravaRetriableError on 429', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=444',
          _MockResponse(429, 'rate limited'),
        );

        final client = createClient();
        expect(
          () => client.pollUpload(444, maxAttempts: 1),
          throwsA(isA<StravaRetriableError>()),
        );
      });

      test('throws StravaWebUploadError on 500', () async {
        adapter.onGet(
          'https://www.strava.com/upload/progress.json?ids%5B%5D=555',
          _MockResponse(500, 'server error'),
        );

        final client = createClient();
        expect(
          () => client.pollUpload(555, maxAttempts: 1),
          throwsA(isA<StravaWebUploadError>()),
        );
      });
    });

    group('isSessionValid', () {
      test('returns true on 200', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(200, '<html></html>'),
        );

        final client = createClient();
        expect(await client.isSessionValid(), isTrue);
      });

      test('returns false on 302', () async {
        adapter.onGet(
          'https://www.strava.com/upload/select',
          _MockResponse(
            302,
            '',
            headers: {
              'location': ['https://www.strava.com/login'],
            },
          ),
        );

        final client = createClient();
        expect(await client.isSessionValid(), isFalse);
      });

      test('returns false on network error', () async {
        // No mock registered — will return 404 "Not mocked"
        final client = createClient();
        expect(await client.isSessionValid(), isFalse);
      });
    });
  });
}
