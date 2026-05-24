import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/strava_client.dart';

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
  group('StravaClient.uploadFit', () {
    test('uploads .fit files with fit data_type', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'strava-client-fit-',
      );
      final File fitFile = File('${tempDir.path}/demo.fit');
      await fitFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Dio dio = Dio();
      late Map<String, dynamic> fields;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString() == 'https://www.strava.com/api/v3/uploads') {
          fields = <String, dynamic>{
            for (final MapEntry<String, String> entry in options.data.fields)
              entry.key: entry.value,
          };
          return ResponseBody.fromString(
            jsonEncode({'id': 123}),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/json'],
            },
          );
        }
        return ResponseBody.fromString('not found', 404);
      });

      final StravaClient client = StravaClient(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        accessToken: 'access-token',
        expiresAt: 4102444800,
        dio: dio,
      );

      await client.uploadFit(fitFile);

      expect(fields['data_type'], 'fit');
    });

    test('uploads .gpx files with gpx data_type case-insensitively', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'strava-client-gpx-',
      );
      final File gpxFile = File('${tempDir.path}/demo.GPX');
      await gpxFile.writeAsString('<gpx></gpx>');

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Dio dio = Dio();
      late Map<String, dynamic> fields;
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString() == 'https://www.strava.com/api/v3/uploads') {
          fields = <String, dynamic>{
            for (final MapEntry<String, String> entry in options.data.fields)
              entry.key: entry.value,
          };
          return ResponseBody.fromString(
            jsonEncode({'id': 456}),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/json'],
            },
          );
        }
        return ResponseBody.fromString('not found', 404);
      });

      final StravaClient client = StravaClient(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        accessToken: 'access-token',
        expiresAt: 4102444800,
        dio: dio,
      );

      await client.uploadFit(gpxFile);

      expect(fields['data_type'], 'gpx');
    });
  });

  group('StravaClient.activityExists', () {
    test('returns true when activity exists', () async {
      final Dio dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        if (options.uri.toString().contains('/api/v3/activities/123')) {
          return ResponseBody.fromString(
            jsonEncode({'id': 123, 'name': 'Test'}),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/json'],
            },
          );
        }
        return ResponseBody.fromString('not found', 404);
      });

      final client = StravaClient(
        clientId: 'id',
        clientSecret: 'secret',
        refreshToken: 'refresh',
        accessToken: 'valid-token',
        expiresAt: 4102444800,
        dio: dio,
      );

      expect(await client.activityExists(123), isTrue);
    });

    test('returns false when activity is deleted (404)', () async {
      final Dio dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          '{"errors": [{"resource": "Activity", "code": "not found"}]}',
          404,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      final client = StravaClient(
        clientId: 'id',
        clientSecret: 'secret',
        refreshToken: 'refresh',
        accessToken: 'valid-token',
        expiresAt: 4102444800,
        dio: dio,
      );

      expect(await client.activityExists(999), isFalse);
    });
  });
}
