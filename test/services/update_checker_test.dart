import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/update_checker.dart';

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

Dio _mockDio(Future<ResponseBody> Function(RequestOptions) handler) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeHttpClientAdapter(handler);
  return dio;
}

ResponseBody _jsonResponse(Map<String, dynamic> data, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

/// Assets covering every platform the checker matches, so "has update" style
/// assertions hold on any CI runner (macOS, Linux, Windows, Android).
List<Map<String, dynamic>> _allPlatformAssets() => [
  {'name': 'app-release.apk'},
  {'name': 'app-release.dmg'},
  {'name': 'app.ipa'},
  {'name': 'app-release.AppImage'},
  {'name': 'app-setup.exe'},
];

void main() {
  group('UpdateChecker.compareVersions', () {
    test('returns 1 when latest is newer (patch)', () {
      expect(UpdateChecker.compareVersions('1.0.20', '1.0.21'), 1);
    });

    test('returns 1 when latest is newer (minor)', () {
      expect(UpdateChecker.compareVersions('1.0.20', '1.1.0'), 1);
    });

    test('returns 1 when latest is newer (major)', () {
      expect(UpdateChecker.compareVersions('1.9.9', '2.0.0'), 1);
    });

    test('returns 0 when versions are equal', () {
      expect(UpdateChecker.compareVersions('1.0.20', '1.0.20'), 0);
    });

    test('returns -1 when current is newer', () {
      expect(UpdateChecker.compareVersions('1.0.21', '1.0.20'), -1);
    });

    test('treats unparseable current version as 0.0.0', () {
      expect(UpdateChecker.compareVersions('abc', '1.0.0'), 1);
    });
  });

  group('UpdateChecker.check', () {
    test('returns hasUpdate true when GitHub has newer version', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({
          'tag_name': 'v99.0.0',
          'body': '## What is new\n- Feature A',
          'assets': _allPlatformAssets(),
        });
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, '99.0.0');
      expect(result.currentVersion, '1.0.0');
      expect(result.releaseNotes, contains('Feature A'));
      expect(result.downloadUrl, contains('releases/tag/v99.0.0'));
    });

    test('returns hasUpdate false when versions are equal', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({'tag_name': 'v1.0.0', 'body': ''});
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isFalse);
    });

    test('returns hasUpdate false when current is newer', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({'tag_name': 'v1.0.0', 'body': ''});
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '2.0.0',
      );

      expect(result.hasUpdate, isFalse);
    });

    test('strips v prefix from tag_name before comparison', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({
          'tag_name': 'v99.0.0',
          'body': '',
          'assets': _allPlatformAssets(),
        });
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.latestVersion, '99.0.0');
      expect(result.downloadUrl, endsWith('/releases/tag/v99.0.0'));
    });

    test('returns hasUpdate false on network error', () async {
      final dio = _mockDio((options) async {
        throw DioException(
          type: DioExceptionType.connectionTimeout,
          requestOptions: options,
        );
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isFalse);
    });

    test('returns hasUpdate false on non-200 status', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({'message': 'rate limit'}, status: 403);
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isFalse);
    });

    test('handles tag_name without v prefix', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({
          'tag_name': '99.0.0',
          'body': '',
          'assets': _allPlatformAssets(),
        });
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, '99.0.0');
    });

    test('handles empty body gracefully', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({
          'tag_name': 'v99.0.0',
          'assets': _allPlatformAssets(),
        });
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isTrue);
      expect(result.releaseNotes, isEmpty);
    });

    test(
      'returns hasUpdate false when no asset matches current platform',
      () async {
        final dio = _mockDio((options) async {
          return _jsonResponse({
            'tag_name': 'v99.0.0',
            'body': '',
            'assets': [
              {'name': 'app-release.apk'},
            ],
          });
        });

        final result = await UpdateChecker.check(
          dio: dio,
          currentVersion: '1.0.0',
        );

        expect(result.hasUpdate, isFalse);
      },
    );

    test('returns hasUpdate false when assets list is empty', () async {
      final dio = _mockDio((options) async {
        return _jsonResponse({
          'tag_name': 'v99.0.0',
          'body': '',
          'assets': <Map<String, dynamic>>[],
        });
      });

      final result = await UpdateChecker.check(
        dio: dio,
        currentVersion: '1.0.0',
      );

      expect(result.hasUpdate, isFalse);
    });
  });
}
