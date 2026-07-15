# 配置文件导出与导入 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 支持将应用设置导出为 JSON 文件并从 JSON 文件导入，实现跨设备配置迁移，格式向后版本兼容。

**Architecture:** 新增 `AppConfig` 数据类负责序列化/反序列化，`ConfigService` 负责导出/导入业务逻辑，设置页面新增"配置文件管理"区域。使用 `file_picker` 选择文件，`share_plus` 分享导出文件。

**Tech Stack:** Flutter/Dart, file_picker, share_plus, package_info_plus (已有)

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `pubspec.yaml` | 修改 | 添加 file_picker、share_plus 依赖 |
| `lib/models/app_config.dart` | 新建 | AppConfig 数据类，序列化/反序列化，版本校验 |
| `lib/services/config_service.dart` | 新建 | 导出/导入业务逻辑 |
| `lib/screens/settings_screen.dart` | 修改 | 新增"配置文件管理"UI 区域 |
| `test/models/app_config_test.dart` | 新建 | AppConfig 单元测试 |
| `test/services/config_service_test.dart` | 新建 | ConfigService 单元测试 |

---

## Task 1: 添加依赖

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: 添加 file_picker 和 share_plus 依赖**

在 `pubspec.yaml` 的 `dependencies` 下添加：

```yaml
  file_picker: ^8.1.7
  share_plus: ^10.1.4
```

- [ ] **Step 2: 运行 flutter pub get**

Run: `flutter pub get`
Expected: 依赖安装成功，无错误

- [ ] **Step 3: 提交**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "deps: add file_picker and share_plus for config export/import"
```

---

## Task 2: 创建 AppConfig 数据类

**Files:**
- Create: `lib/models/app_config.dart`
- Test: `test/models/app_config_test.dart`

- [ ] **Step 1: 编写 AppConfig 测试**

创建 `test/models/app_config_test.dart`：

```dart
import 'dart:convert';
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
      // Note: round-trip preserves the exact value passed in
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/models/app_config_test.dart`
Expected: FAIL — `AppConfig` 类不存在

- [ ] **Step 3: 实现 AppConfig**

创建 `lib/models/app_config.dart`：

```dart
class AppConfig {
  static const int currentVersion = 1;

  final int version;
  final String appVersion;
  final String exportedAt;
  final Map<String, dynamic> settings;

  const AppConfig({
    required this.version,
    required this.appVersion,
    required this.exportedAt,
    required this.settings,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'appVersion': appVersion,
        'exportedAt': exportedAt,
        'settings': settings,
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('配置文件格式无效：缺少版本信息');
    }
    if (version != currentVersion) {
      throw FormatException('配置文件版本 $version 不受支持');
    }

    return AppConfig(
      version: version,
      appVersion: json['appVersion'] as String? ?? '',
      exportedAt: json['exportedAt'] as String? ?? '',
      settings: Map<String, dynamic>.from(json['settings'] as Map? ?? {}),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models/app_config_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models/app_config.dart test/models/app_config_test.dart
git commit -m "feat: add AppConfig model with version validation"
```

---

## Task 3: 创建 ConfigService

**Files:**
- Create: `lib/services/config_service.dart`
- Test: `test/services/config_service_test.dart`

- [ ] **Step 1: 编写 ConfigService 测试**

创建 `test/services/config_service_test.dart`：

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/config_service.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class _FakeSettingsStore implements SettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<Map<String, String>> readAll() async => Map.from(_values);

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}

void main() {
  group('ConfigService', () {
    late _FakeSettingsStore store;
    late SettingsService settingsService;
    late ConfigService configService;

    setUp(() {
      store = _FakeSettingsStore();
      settingsService = SettingsService(store: store);
      configService = ConfigService(settingsService: settingsService);
    });

    test('exportConfig includes all settings keys', () async {
      await settingsService.saveSettings({
        SettingsService.keyOneLapUsername: 'user',
        SettingsService.keyOneLapPassword: 'pass',
        SettingsService.keyStravaClientId: '123',
        SettingsService.keyLookbackDays: '5',
      });

      final jsonStr = await configService.exportConfig(appVersion: '1.0.21');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(json['version'], 1);
      expect(json['appVersion'], '1.0.21');
      expect(json['exportedAt'], isNotEmpty);

      final settings = json['settings'] as Map<String, dynamic>;
      final onelap = settings['onelap'] as Map<String, dynamic>;
      expect(onelap['username'], 'user');
      expect(onelap['password'], 'pass');

      final strava = settings['strava'] as Map<String, dynamic>;
      expect(strava['clientId'], '123');

      final sync = settings['sync'] as Map<String, dynamic>;
      expect(sync['lookbackDays'], 5);
    });

    test('exportConfig maps storage keys to structured JSON', () async {
      await settingsService.saveSettings({
        SettingsService.keyLookbackDays: '7',
        SettingsService.keyGcjCorrectionEnabled: 'true',
        SettingsService.keyUploadToStrava: 'true',
        SettingsService.keyUploadToXingzhe: 'false',
      });

      final jsonStr = await configService.exportConfig(appVersion: '1.0.0');
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final sync = (json['settings'] as Map<String, dynamic>)['sync']
          as Map<String, dynamic>;

      expect(sync['lookbackDays'], 7);
      expect(sync['gcjCorrectionEnabled'], true);
      expect(sync['uploadToStrava'], true);
      expect(sync['uploadToXingzhe'], false);
    });

    test('importConfig writes all settings to store', () async {
      final configJson = jsonEncode({
        'version': 1,
        'appVersion': '1.0.0',
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'settings': {
          'onelap': {'username': 'imported_user', 'password': 'imported_pass'},
          'strava': {
            'uploadMode': 'web',
            'clientId': '456',
            'clientSecret': 'sec',
            'refreshToken': 'rt',
            'accessToken': 'at',
            'expiresAt': '123',
            'webCookies': 'cookies',
          },
          'xingzhe': {
            'username': 'xz_user',
            'password': 'xz_pass',
            'sessionId': 'sid',
          },
          'intervalsIcu': {'athleteId': 'a1', 'apiKey': 'k1'},
          'sync': {
            'lookbackDays': 10,
            'gcjCorrectionEnabled': true,
            'uploadToStrava': true,
            'uploadToXingzhe': true,
            'uploadToIntervalsIcu': true,
          },
        },
      });

      await configService.importConfig(configJson);

      final settings = await settingsService.loadSettings();
      expect(settings[SettingsService.keyOneLapUsername], 'imported_user');
      expect(settings[SettingsService.keyOneLapPassword], 'imported_pass');
      expect(settings[SettingsService.keyStravaClientId], '456');
      expect(settings[SettingsService.keyStravaUploadMode], 'web');
      expect(settings[SettingsService.keyLookbackDays], '10');
      expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
      expect(settings[SettingsService.keyUploadToXingzhe], 'true');
    });

    test('importConfig throws on invalid JSON', () {
      expect(
        () => configService.importConfig('not json'),
        throwsFormatException,
      );
    });

    test('importConfig throws on missing version', () {
      final json = jsonEncode({
        'appVersion': '1.0.0',
        'settings': <String, dynamic>{},
      });
      expect(
        () => configService.importConfig(json),
        throwsFormatException,
      );
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/config_service_test.dart`
Expected: FAIL — `ConfigService` 类不存在

- [ ] **Step 3: 实现 ConfigService**

创建 `lib/services/config_service.dart`：

```dart
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/config_service_test.dart`
Expected: 全部 PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/config_service.dart test/services/config_service_test.dart
git commit -m "feat: add ConfigService with export/import logic"
```

---

## Task 4: 设置页面新增配置文件管理 UI

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: 添加 import**

在 `settings_screen.dart` 顶部添加：

```dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/config_service.dart';
```

- [ ] **Step 2: 添加 ConfigService 和状态变量**

在 `_SettingsScreenState` 类中添加：

```dart
  late final ConfigService _configService;
  bool _exporting = false;
  bool _importing = false;
```

在 `initState` 中初始化 `_configService`：

```dart
    _configService = ConfigService(settingsService: _settingsService);
```

- [ ] **Step 3: 添加导出方法**

```dart
  Future<void> _exportConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出配置'),
        content: const Text('配置文件包含账号密码等敏感信息，请妥善保管。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _exporting = true);
    try {
      final json = await _configService.exportConfig();
      final tempDir = await Directory.systemTemp.createTemp('config');
      final file = File('${tempDir.path}/onelap_config.json');
      await file.writeAsString(json);
      await Share.shareXFiles([file.path], text: 'WanSync 配置文件');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
```

- [ ] **Step 4: 添加导入方法**

```dart
  Future<void> _importConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入配置'),
        content: const Text('将覆盖所有当前设置，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final json = await file.readAsString();
      await _configService.importConfig(json);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已导入')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
```

- [ ] **Step 5: 添加 UI 区域**

在 `build` 方法的 `ListView.children` 列表末尾（`_buildPlatformCard` for Intervals.icu 之后）添加：

```dart
          const SizedBox(height: 16),
          const Text(
            '配置文件管理',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _exporting ? null : _exportConfig,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload),
                  label: const Text('导出配置'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _importing ? null : _importConfig,
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('导入配置'),
                ),
              ),
            ],
          ),
```

- [ ] **Step 6: 运行格式化和分析**

Run:
```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
```

Expected: 无格式错误，无分析警告

- [ ] **Step 7: 运行全部测试**

Run: `flutter test`
Expected: 全部 PASS

- [ ] **Step 8: 提交**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add config export/import UI to settings screen"
```
