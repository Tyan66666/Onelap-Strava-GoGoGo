import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/outbase_client.dart';

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}

void main() {
  group('OutbaseClient.uploadFit', () {
    late Directory tempDir;
    late File fitFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('outbase-');
      fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3, 4, 5]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test(
      'returns success when CDN upload and API registration succeed',
      () async {
        var callCount = 0;
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          callCount++;
          if (options.uri.toString().contains('resource/upload')) {
            // CDN upload
            return ResponseBody.fromString(
              jsonEncode({'message': 'SUCCESS', 'data': {}}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API registration
          return ResponseBody.fromString(
            jsonEncode({'ec': 0, 'em': '', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);
        final result = await client.uploadFit(fitFile);

        expect(result.success, true);
        expect(result.alreadyUploaded, false);
        expect(callCount, 2);
      },
    );

    test(
      'returns alreadyUploaded when API returns duplicate message',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'SUCCESS', 'data': {}}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API registration - duplicate
          return ResponseBody.fromString(
            jsonEncode({'ec': 1, 'em': '相同时间内已存在其他运动数据', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);
        final result = await client.uploadFit(fitFile);

        expect(result.success, false);
        expect(result.alreadyUploaded, true);
      },
    );

    test('throws OutbasePermanentError when CDN upload returns 4xx', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Bad Request', 400);
      });

      final client = OutbaseClient(sessionId: 'test-session', dio: dio);

      expect(
        () => client.uploadFit(fitFile),
        throwsA(isA<OutbasePermanentError>()),
      );
    });

    test(
      'throws OutbaseRetriableError when CDN upload has network error',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          throw DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: options,
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);

        expect(
          () => client.uploadFit(fitFile),
          throwsA(isA<OutbaseRetriableError>()),
        );
      },
    );

    test(
      'throws OutbasePermanentError when CDN succeeds but API returns 4xx',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'SUCCESS', 'data': {}}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API registration fails with 400
          return ResponseBody.fromString('Bad Request', 400);
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);

        expect(
          () => client.uploadFit(fitFile),
          throwsA(isA<OutbasePermanentError>()),
        );
      },
    );

    test(
      'throws OutbaseRetriableError when CDN succeeds but API has network error',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'SUCCESS', 'data': {}}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          throw DioException(
            type: DioExceptionType.connectionTimeout,
            requestOptions: options,
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);

        expect(
          () => client.uploadFit(fitFile),
          throwsA(isA<OutbaseRetriableError>()),
        );
      },
    );

    test('throws OutbasePermanentError on 401 session expired', () async {
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString().contains('resource/upload')) {
          return ResponseBody.fromString(
            jsonEncode({'message': 'SUCCESS', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }
        // API returns 401
        return ResponseBody.fromString('Unauthorized', 401);
      });

      final client = OutbaseClient(sessionId: 'test-session', dio: dio);

      expect(
        () => client.uploadFit(fitFile),
        throwsA(isA<OutbasePermanentError>()),
      );
    });

    test(
      'proceeds to API registration when CDN returns 400 with duplicate indication',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            // CDN returns 400 with "already exists" message
            return ResponseBody.fromString(
              jsonEncode({'message': 'file already exists'}),
              400,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API registration succeeds
          return ResponseBody.fromString(
            jsonEncode({'ec': 0, 'em': '', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);
        final result = await client.uploadFit(fitFile);

        expect(result.success, true);
        expect(result.alreadyUploaded, false);
      },
    );

    test(
      'returns alreadyUploaded when CDN duplicate and API returns duplicate message',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'file already exists'}),
              400,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API returns duplicate message
          return ResponseBody.fromString(
            jsonEncode({'ec': 1, 'em': '相同时间内已存在其他运动数据', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);
        final result = await client.uploadFit(fitFile);

        expect(result.success, false);
        expect(result.alreadyUploaded, true);
      },
    );

    test(
      'throws OutbasePermanentError when CDN 400 has no duplicate indication',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'Invalid file format'}),
              400,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          return ResponseBody.fromString(
            jsonEncode({'ec': 0, 'em': '', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);

        expect(
          () => client.uploadFit(fitFile),
          throwsA(isA<OutbasePermanentError>()),
        );
      },
    );

    test(
      'throws OutbasePermanentError when API returns "Please log in"',
      () async {
        final dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          if (options.uri.toString().contains('resource/upload')) {
            return ResponseBody.fromString(
              jsonEncode({'message': 'SUCCESS', 'data': {}}),
              200,
              headers: {
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }
          // API returns "Please log in"
          return ResponseBody.fromString(
            jsonEncode({'ec': 1, 'em': 'Please log in', 'data': {}}),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        });

        final client = OutbaseClient(sessionId: 'test-session', dio: dio);

        expect(
          () => client.uploadFit(fitFile),
          throwsA(isA<OutbasePermanentError>()),
        );
      },
    );
  });
}
