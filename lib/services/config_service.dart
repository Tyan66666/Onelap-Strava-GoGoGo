import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_config.dart';
import 'settings_service.dart';

class ConfigService {
  final SettingsService _settingsService;

  ConfigService({required SettingsService settingsService})
      : _settingsService = settingsService;

  Future<String> exportConfig({String? appVersion}) async {
    final version = appVersion ?? (await PackageInfo.fromPlatform()).version;
    final settings = await _settingsService.loadSettings();

    final config = AppConfig(
      version: AppConfig.currentVersion,
      appVersion: version,
      exportedAt: DateTime.now().toUtc().toIso8601String(),
      settings: _settingsToJson(settings),
    );

    return const JsonEncoder.withIndent('  ').convert(config.toJson());
  }

  Future<void> importConfig(String jsonStr) async {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('配置文件格式无效');
    }

    final config = AppConfig.fromJson(json);
    final settingsMap = _jsonToSettings(config.settings);
    await _settingsService.saveSettings(settingsMap);
  }

  Map<String, dynamic> _settingsToJson(Map<String, String> settings) {
    return {
      'onelap': {
        'username': settings[SettingsService.keyOneLapUsername] ?? '',
        'password': settings[SettingsService.keyOneLapPassword] ?? '',
      },
      'strava': {
        'uploadMode': settings[SettingsService.keyStravaUploadMode] ?? 'api',
        'clientId': settings[SettingsService.keyStravaClientId] ?? '',
        'clientSecret': settings[SettingsService.keyStravaClientSecret] ?? '',
        'refreshToken': settings[SettingsService.keyStravaRefreshToken] ?? '',
        'accessToken': settings[SettingsService.keyStravaAccessToken] ?? '',
        'expiresAt': settings[SettingsService.keyStravaExpiresAt] ?? '',
        'webCookies': settings[SettingsService.keyStravaWebCookies] ?? '',
      },
      'xingzhe': {
        'username': settings[SettingsService.keyXingzheUsername] ?? '',
        'password': settings[SettingsService.keyXingzhePassword] ?? '',
        'sessionId': settings[SettingsService.keyXingzheSessionId] ?? '',
      },
      'intervalsIcu': {
        'athleteId': settings[SettingsService.keyIntervalsIcuAthleteId] ?? '',
        'apiKey': settings[SettingsService.keyIntervalsIcuApiKey] ?? '',
      },
      'sync': {
        'lookbackDays':
            int.tryParse(settings[SettingsService.keyLookbackDays] ?? '') ?? 3,
        'gcjCorrectionEnabled':
            settings[SettingsService.keyGcjCorrectionEnabled] == 'true',
        'uploadToStrava':
            settings[SettingsService.keyUploadToStrava] != 'false',
        'uploadToXingzhe':
            settings[SettingsService.keyUploadToXingzhe] == 'true',
        'uploadToIntervalsIcu':
            settings[SettingsService.keyUploadToIntervalsIcu] == 'true',
      },
    };
  }

  Map<String, String> _jsonToSettings(Map<String, dynamic> json) {
    final onelap = _castMap(json['onelap']);
    final strava = _castMap(json['strava']);
    final xingzhe = _castMap(json['xingzhe']);
    final intervalsIcu = _castMap(json['intervalsIcu']);
    final sync = _castMap(json['sync']);

    return {
      SettingsService.keyOneLapUsername: onelap['username'] ?? '',
      SettingsService.keyOneLapPassword: onelap['password'] ?? '',
      SettingsService.keyStravaUploadMode: strava['uploadMode'] ?? 'api',
      SettingsService.keyStravaClientId: strava['clientId'] ?? '',
      SettingsService.keyStravaClientSecret: strava['clientSecret'] ?? '',
      SettingsService.keyStravaRefreshToken: strava['refreshToken'] ?? '',
      SettingsService.keyStravaAccessToken: strava['accessToken'] ?? '',
      SettingsService.keyStravaExpiresAt: strava['expiresAt'] ?? '',
      SettingsService.keyStravaWebCookies: strava['webCookies'] ?? '',
      SettingsService.keyXingzheUsername: xingzhe['username'] ?? '',
      SettingsService.keyXingzhePassword: xingzhe['password'] ?? '',
      SettingsService.keyXingzheSessionId: xingzhe['sessionId'] ?? '',
      SettingsService.keyIntervalsIcuAthleteId: intervalsIcu['athleteId'] ?? '',
      SettingsService.keyIntervalsIcuApiKey: intervalsIcu['apiKey'] ?? '',
      SettingsService.keyLookbackDays: (sync['lookbackDays'] ?? 3).toString(),
      SettingsService.keyGcjCorrectionEnabled:
          (sync['gcjCorrectionEnabled'] ?? false).toString(),
      SettingsService.keyUploadToStrava:
          (sync['uploadToStrava'] ?? true).toString(),
      SettingsService.keyUploadToXingzhe:
          (sync['uploadToXingzhe'] ?? false).toString(),
      SettingsService.keyUploadToIntervalsIcu:
          (sync['uploadToIntervalsIcu'] ?? false).toString(),
    };
  }

  static Map<String, dynamic> _castMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }
}
