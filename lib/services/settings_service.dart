import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SettingsStore {
  Future<Map<String, String>> readAll();

  Future<void> write({required String key, required String value});
}

class SecureSettingsStore implements SettingsStore {
  const SecureSettingsStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<Map<String, String>> readAll() {
    return _storage.readAll();
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }
}

class SettingsService {
  SettingsService({SettingsStore? store})
    : _store = store ?? const SecureSettingsStore();

  final SettingsStore _store;

  static const keyOneLapUsername = 'ONELAP_USERNAME';
  static const keyOneLapPassword = 'ONELAP_PASSWORD';
  static const keyStravaClientId = 'STRAVA_CLIENT_ID';
  static const keyStravaClientSecret = 'STRAVA_CLIENT_SECRET';
  static const keyStravaRefreshToken = 'STRAVA_REFRESH_TOKEN';
  static const keyStravaAccessToken = 'STRAVA_ACCESS_TOKEN';
  static const keyStravaExpiresAt = 'STRAVA_EXPIRES_AT';
  static const keyXingzheUsername = 'XINGZHE_USERNAME';
  static const keyXingzhePassword = 'XINGZHE_PASSWORD';
  static const keyXingzheSessionId = 'XINGZHE_SESSION_ID';
  static const keyLookbackDays = 'LOOKBACK_DAYS';
  static const keyGcjCorrectionEnabled = 'GCJ_CORRECTION_ENABLED';
  static const keyUploadToStrava = 'UPLOAD_TO_STRAVA';
  static const keyUploadToXingzhe = 'UPLOAD_TO_XINGZHE';

  static const allKeys = [
    keyOneLapUsername,
    keyOneLapPassword,
    keyStravaClientId,
    keyStravaClientSecret,
    keyStravaRefreshToken,
    keyStravaAccessToken,
    keyStravaExpiresAt,
    keyXingzheUsername,
    keyXingzhePassword,
    keyXingzheSessionId,
    keyLookbackDays,
    keyGcjCorrectionEnabled,
    keyUploadToStrava,
    keyUploadToXingzhe,
  ];

  Future<Map<String, String>> loadSettings() async {
    final storedValues = await _store.readAll();
    return <String, String>{
      for (final key in allKeys) key: storedValues[key] ?? '',
    };
  }

  Future<void> saveSettings(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _store.write(key: entry.key, value: entry.value);
    }
  }
}
