import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/xingzhe_client.dart';

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
  group('XingzheClient.login', () {
    test('sanitizes secrets from login failure errors', () async {
      const String username = 'sensitive-user@example.com';
      const String password = 'SuperSecretPassword!';
      const String sessionId = 'sessionid-secret-123';
      const String authHeader = 'Bearer auth-secret-456';
      const String encryptedPassword = 'encrypted-secret-789';

      final Dio dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode(<String, String>{
            'message': 'login failed for $username',
            'cookie': 'sessionid=$sessionId',
            'authorization': authHeader,
            'password': password,
            'encrypted_password': encryptedPassword,
          }),
          401,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      await expectLater(
        () => XingzheClient.login(
          username: username,
          password: password,
          dio: dio,
        ),
        throwsA(
          isA<XingzhePermanentError>().having(
            (XingzhePermanentError error) => error.toString(),
            'error string',
            allOf(
              contains('401'),
              isNot(contains(username)),
              isNot(contains(password)),
              isNot(contains(sessionId)),
              isNot(contains(authHeader)),
              isNot(contains(encryptedPassword)),
            ),
          ),
        ),
      );
    });
  });

  group('XingzheClient.uploadFit', () {
    test('sanitizes secrets while preserving safe HTTP error detail', () async {
      const String username = 'sensitive-user@example.com';
      const String password = 'SuperSecretPassword!';
      const String sessionId = 'sessionid-secret-123';
      const String authHeader = 'authorization=Bearer auth-secret-456';
      const String authToken = 'auth-secret-456';
      const String encryptedPassword =
          'encrypted_password=encrypted-secret-789';

      final Directory tempDir = await Directory.systemTemp.createTemp(
        'xingzhe-client-http-test-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(const <int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Dio dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{
            'msg':
                'invalid fit for $username sessionid=$sessionId password=$password $authHeader $encryptedPassword',
          }),
          400,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      final XingzheClient client = XingzheClient(
        username: username,
        password: password,
        dio: dio,
      );

      await expectLater(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(
          isA<XingzhePermanentError>().having(
            (XingzhePermanentError error) => error.toString(),
            'error string',
            allOf(<Matcher>[
              contains('HTTP 400'),
              contains('invalid fit'),
              isNot(contains(username)),
              isNot(contains(password)),
              isNot(contains(sessionId)),
              isNot(contains(authHeader)),
              isNot(contains(authToken)),
              isNot(contains(encryptedPassword)),
            ]),
          ),
        ),
      );
    });

    test('falls back when upload failure detail is missing', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'xingzhe-client-null-msg-test-',
      );
      final File fitFile = File('${tempDir.path}/activity.fit');
      await fitFile.writeAsBytes(const <int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final Dio dio = Dio();
      dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
        return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{'code': 1001}),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      });

      final XingzheClient client = XingzheClient(
        username: 'user',
        password: 'pass',
        dio: dio,
      );

      await expectLater(
        () => client.uploadFit(fitFile, retries: 1),
        throwsA(
          isA<XingzhePermanentError>().having(
            (XingzhePermanentError error) => error.toString(),
            'error string',
            contains('xingzhe upload failed'),
          ),
        ),
      );
    });

    test(
      'sanitizes secrets while preserving safe upload failure detail',
      () async {
        const String username = 'sensitive-user@example.com';
        const String password = 'SuperSecretPassword!';
        const String sessionId = 'sessionid-secret-123';

        final Directory tempDir = await Directory.systemTemp.createTemp(
          'xingzhe-client-test-',
        );
        final File fitFile = File('${tempDir.path}/activity.fit');
        await fitFile.writeAsBytes(const <int>[1, 2, 3]);

        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });

        final Dio dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          return ResponseBody.fromString(
            jsonEncode(<String, dynamic>{
              'code': 1001,
              'msg':
                  'invalid fit for $username sessionid=$sessionId password=$password',
            }),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>['application/json'],
            },
          );
        });

        final XingzheClient client = XingzheClient(
          username: username,
          password: password,
          dio: dio,
        );

        await expectLater(
          () => client.uploadFit(fitFile, retries: 1),
          throwsA(
            isA<XingzhePermanentError>().having(
              (XingzhePermanentError error) => error.toString(),
              'error string',
              allOf(
                contains('invalid fit'),
                isNot(contains(username)),
                isNot(contains(password)),
                isNot(contains(sessionId)),
              ),
            ),
          ),
        );
      },
    );
  });
}
