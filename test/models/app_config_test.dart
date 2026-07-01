import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/app_config.dart';

void main() {
  group('AppConfig', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      final config = AppConfig(
        version: 1,
        appVersion: '1.0.21',
        exportedAt: '2026-07-02T10:00:00.000Z',
        settings: {
          'onelap': {'username': 'user', 'password': 'pass'},
          'strava': {'uploadMode': 'api', 'clientId': '123'},
          'sync': {'lookbackDays': 3, 'gcjCorrectionEnabled': false},
        },
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.version, 1);
      expect(restored.appVersion, '1.0.21');
      expect(restored.exportedAt, '2026-07-02T10:00:00.000Z');
      expect(restored.settings['onelap']['username'], 'user');
      expect(restored.settings['sync']['lookbackDays'], 3);
    });

    test('fromJson accepts version 1', () {
      final json = {
        'version': 1,
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': <String, dynamic>{},
      };
      final config = AppConfig.fromJson(json);
      expect(config.version, 1);
    });

    test('fromJson throws on missing version', () {
      final json = {
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': <String, dynamic>{},
      };
      expect(() => AppConfig.fromJson(json), throwsFormatException);
    });

    test('fromJson throws on unsupported version', () {
      final json = {
        'version': 999,
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': <String, dynamic>{},
      };
      expect(() => AppConfig.fromJson(json), throwsFormatException);
    });

    test('fromJson ignores unknown top-level fields', () {
      final json = {
        'version': 1,
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': <String, dynamic>{},
        'futureField': 'should be ignored',
      };
      final config = AppConfig.fromJson(json);
      expect(config.version, 1);
    });

    test('fromJson handles missing settings sections gracefully', () {
      final json = {
        'version': 1,
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': <String, dynamic>{},
      };
      final config = AppConfig.fromJson(json);
      expect(config.settings, isEmpty);
    });
  });
}
