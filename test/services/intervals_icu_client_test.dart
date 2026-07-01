import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/intervals_icu_client.dart';

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
  group('IntervalsIcuClient.uploadFit', () {
    test('returns activity id on 201', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode({'id': 789}),
          201,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      final id = await client.uploadFit(fitFile);
      expect(id, 789);
    });

    test('treats 200 as success (duplicate)', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{}),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      final id = await client.uploadFit(fitFile);
      expect(id, 0);
    });

    test('throws IntervalsIcuPermanentError on 401', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Unauthorized', 401);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuPermanentError>()),
      );
    });

    test('throws IntervalsIcuRetriableError on 5xx', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Internal Server Error', 500);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuRetriableError>()),
      );
    });

    test('throws IntervalsIcuRetriableError on 429', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Too Many Requests', 429);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuRetriableError>()),
      );
    });

    test('rethrows network error without response', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        throw DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: options,
          error: 'Connection timed out',
        );
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<DioException>()),
      );
    });

    test('returns 0 when response body is not a Map', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          'plain text response',
          201,
          headers: {
            Headers.contentTypeHeader: ['text/plain'],
          },
        );
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      final id = await client.uploadFit(fitFile);
      expect(id, 0);
    });

    test('throws IntervalsIcuPermanentError on 400', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Bad Request', 400);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuPermanentError>()),
      );
    });

    test('throws IntervalsIcuPermanentError on 403', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Forbidden', 403);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuPermanentError>()),
      );
    });

    test('throws IntervalsIcuPermanentError on 404', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString('Not Found', 404);
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'test-key',
        dio: dio,
      );

      expect(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(isA<IntervalsIcuPermanentError>()),
      );
    });

    test('sends Basic auth header with API_KEY prefix', () async {
      final tempDir = await Directory.systemTemp.createTemp('intervals-icu-');
      final fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      String? capturedAuthHeader;
      final dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        capturedAuthHeader = options.headers['Authorization'] as String?;
        return ResponseBody.fromString(
          jsonEncode({'id': 1}),
          201,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      });

      final client = IntervalsIcuClient(
        athleteId: '123',
        apiKey: 'my-secret-key',
        dio: dio,
      );

      await client.uploadFit(fitFile);

      final expectedToken = base64.encode(utf8.encode('API_KEY:my-secret-key'));
      expect(capturedAuthHeader, 'Basic $expectedToken');
    });
  });
}
