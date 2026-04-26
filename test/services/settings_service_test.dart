import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class _RecordingSecureStoragePlatform extends TestFlutterSecureStoragePlatform {
  _RecordingSecureStoragePlatform() : super(<String, String>{});

  Map<String, String>? lastWriteOptions;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    lastWriteOptions = Map<String, String>.from(options);
    await super.write(key: key, value: value, options: options);
  }
}

class _ReadAllFailingSecureStoragePlatform extends TestFlutterSecureStoragePlatform {
  _ReadAllFailingSecureStoragePlatform(super.data);

  int readAllCallCount = 0;
  int readCallCount = 0;

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    readAllCallCount += 1;
    throw PlatformException(
      code: 'Unexpected security result code',
      message:
          'Code: -50, Message: One or more parameters passed to a function were not valid.',
      details: -50,
    );
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    readCallCount += 1;
    return super.read(key: key, options: options);
  }
}

class _ConcurrentUnsafeStore implements SettingsStore {
  final Map<String, String> _values = <String, String>{};
  bool _writeInFlight = false;

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.from(_values);

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (_writeInFlight) {
      await Future<void>.delayed(Duration.zero);
      return;
    }

    _writeInFlight = true;
    await Future<void>.delayed(Duration.zero);
    _values[key] = value;
    _writeInFlight = false;
  }
}

void main() {
  test(
    'loadSettings returns gcj correction setting while preserving existing keys',
    () async {
      final _ConcurrentUnsafeStore store = _ConcurrentUnsafeStore();
      final SettingsService service = SettingsService(store: store);

      await service.saveSettings(<String, String>{
        SettingsService.keyLookbackDays: '7',
        SettingsService.keyGcjCorrectionEnabled: 'true',
      });

      final Map<String, String> settings = await service.loadSettings();
      expect(settings[SettingsService.keyLookbackDays], '7');
      expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
      expect(settings[SettingsService.keyStravaClientId], '');
    },
  );

  test(
    'saveSettings persists all values even when backend is concurrency-unsafe',
    () async {
      final _ConcurrentUnsafeStore store = _ConcurrentUnsafeStore();
      final SettingsService service = SettingsService(store: store);

      await service.saveSettings(<String, String>{
        SettingsService.keyStravaClientId: '12345',
        SettingsService.keyStravaClientSecret: 'secret-xyz',
        SettingsService.keyOneLapUsername: 'rider@example.com',
        SettingsService.keyOneLapPassword: 'pass-123',
      });

      final Map<String, String> settings = await service.loadSettings();
      expect(settings[SettingsService.keyStravaClientId], '12345');
      expect(settings[SettingsService.keyStravaClientSecret], 'secret-xyz');
      expect(settings[SettingsService.keyOneLapUsername], 'rider@example.com');
      expect(settings[SettingsService.keyOneLapPassword], 'pass-123');
    },
  );

  test(
    'SecureSettingsStore disables data protection keychain on macOS',
    () async {
      if (!Platform.isMacOS) {
        return;
      }

      final FlutterSecureStoragePlatform originalPlatform =
          FlutterSecureStoragePlatform.instance;
      final _RecordingSecureStoragePlatform recordingPlatform =
          _RecordingSecureStoragePlatform();
      FlutterSecureStoragePlatform.instance = recordingPlatform;
      addTearDown(() {
        FlutterSecureStoragePlatform.instance = originalPlatform;
      });

      const SecureSettingsStore store = SecureSettingsStore();
      await store.write(key: 'TEST_KEY', value: 'TEST_VALUE');

      expect(recordingPlatform.lastWriteOptions, isNotNull);
      expect(
        recordingPlatform.lastWriteOptions!['useDataProtectionKeyChain'],
        'false',
      );
    },
  );

  test(
    'loadSettings falls back to per-key reads on macOS when secure storage readAll fails',
    () async {
      if (!Platform.isMacOS) {
        return;
      }

      final FlutterSecureStoragePlatform originalPlatform =
          FlutterSecureStoragePlatform.instance;
      final _ReadAllFailingSecureStoragePlatform fallbackPlatform =
          _ReadAllFailingSecureStoragePlatform(<String, String>{
            SettingsService.keyOneLapUsername: 'rider@example.com',
            SettingsService.keyLookbackDays: '5',
          });
      FlutterSecureStoragePlatform.instance = fallbackPlatform;
      addTearDown(() {
        FlutterSecureStoragePlatform.instance = originalPlatform;
      });

      final SettingsService service = SettingsService();
      final Map<String, String> settings = await service.loadSettings();

      expect(fallbackPlatform.readAllCallCount, 1);
      expect(fallbackPlatform.readCallCount, SettingsService.allKeys.length);
      expect(settings[SettingsService.keyOneLapUsername], 'rider@example.com');
      expect(settings[SettingsService.keyLookbackDays], '5');
      expect(settings[SettingsService.keyStravaClientId], '');
    },
  );
}
