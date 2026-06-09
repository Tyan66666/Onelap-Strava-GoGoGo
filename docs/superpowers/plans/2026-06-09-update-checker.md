# 版本检查功能实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每次启动 App 时自动检查 GitHub Releases 是否有新版本，有新版本时弹窗提示用户。

**Architecture:** 新增 `UpdateChecker` 服务调用 GitHub Releases API，比较语义化版本号，返回 `UpdateInfo` 数据模型。在 `HomeScreen.initState` 中异步触发检查，有更新时弹出对话框。

**Tech Stack:** Dio (HTTP), package_info_plus (版本获取), url_launcher (打开链接)

---

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/models/update_info.dart` | 新增 | UpdateInfo 不可变数据模型 |
| `lib/services/update_checker.dart` | 新增 | GitHub Releases API 调用 + 版本比较 |
| `test/services/update_checker_test.dart` | 新增 | 版本比较逻辑单元测试 |
| `lib/screens/home_screen.dart` | 修改 | initState 添加检查、新增弹窗方法、关于对话框增加入口 |

---

### Task 1: 创建 UpdateInfo 数据模型

**Files:**
- Create: `lib/models/update_info.dart`

- [ ] **Step 1: 创建 UpdateInfo 类**

```dart
class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;
  final String currentVersion;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateInfo({
    required this.hasUpdate,
    this.latestVersion = '',
    this.currentVersion = '',
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  factory UpdateInfo.noUpdate(String current) => UpdateInfo(
    hasUpdate: false,
    currentVersion: current,
  );
}
```

- [ ] **Step 2: 验证编译通过**

Run: `dart analyze lib/models/update_info.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/models/update_info.dart
git commit -m "feat: add UpdateInfo data model"
```

---

### Task 2: 创建 UpdateChecker 服务 + 测试

**Files:**
- Create: `lib/services/update_checker.dart`
- Create: `test/services/update_checker_test.dart`

- [ ] **Step 1: 编写版本比较逻辑测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/update_checker.dart';

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

    test('returns 0 for invalid version strings', () {
      expect(UpdateChecker.compareVersions('abc', '1.0.0'), 0);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/update_checker_test.dart`
Expected: FAIL (UpdateChecker not found)

- [ ] **Step 3: 实现 UpdateChecker 服务**

```dart
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/update_info.dart';

class UpdateChecker {
  static const _owner = 'Tyan66666';
  static const _repo = 'Onelap-Strava-GoGoGo';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Compare two semantic version strings.
  /// Returns 1 if [latest] > [current], -1 if < , 0 if equal or unparseable.
  static int compareVersions(String current, String latest) {
    try {
      final c = current.split('.').map(int.parse).toList();
      final l = latest.split('.').map(int.parse).toList();
      for (var i = 0; i < 3; i++) {
        final cv = i < c.length ? c[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (lv > cv) return 1;
        if (lv < cv) return -1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<UpdateInfo> check({Dio? dio}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final d = dio ?? Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ));

      final response = await d.get(_apiUrl);
      if (response.statusCode != 200) {
        return UpdateInfo.noUpdate(currentVersion);
      }

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      final body = data['body'] as String? ?? '';

      final comparison = compareVersions(currentVersion, latestVersion);
      if (comparison != 1) {
        return UpdateInfo.noUpdate(currentVersion);
      }

      return UpdateInfo(
        hasUpdate: true,
        latestVersion: latestVersion,
        currentVersion: currentVersion,
        releaseNotes: body,
        downloadUrl: 'https://github.com/$_owner/$_repo/releases/tag/$tagName',
      );
    } catch (_) {
      try {
        final info = await PackageInfo.fromPlatform();
        return UpdateInfo.noUpdate(info.version);
      } catch (_) {
        return const UpdateInfo(hasUpdate: false);
      }
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/update_checker_test.dart`
Expected: All tests PASS

- [ ] **Step 5: 运行全量分析**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/services/update_checker.dart test/services/update_checker_test.dart
git commit -m "feat: add UpdateChecker service with version comparison"
```

---

### Task 3: 集成到 HomeScreen

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 添加 import**

在 `home_screen.dart` 顶部添加：

```dart
import '../models/update_info.dart';
import '../services/update_checker.dart';
```

- [ ] **Step 2: 在 initState 中添加检查调用**

修改 `initState` 方法，在 `_showAboutIfFirstLaunch()` 之后添加 `_checkForUpdate()`：

```dart
@override
void initState() {
  super.initState();
  _loadLastSyncTime();
  _loadBanners();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _showAboutIfFirstLaunch();
    _checkForUpdate();
  });
}
```

- [ ] **Step 3: 添加 _checkForUpdate 方法**

在 `_showAboutIfFirstLaunch` 方法之后添加：

```dart
Future<void> _checkForUpdate() async {
  final updateInfo = await UpdateChecker.check();
  if (!mounted || !updateInfo.hasUpdate) return;
  if (!mounted) return;
  _showUpdateDialog(updateInfo);
}
```

- [ ] **Step 4: 添加 _showUpdateDialog 方法**

在 `_checkForUpdate` 方法之后添加：

```dart
void _showUpdateDialog(UpdateInfo info) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '最新版本: v${info.latestVersion}',
              style: const TextStyle(fontSize: 14),
            ),
            Text(
              '当前版本: v${info.currentVersion}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            if (info.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('更新内容:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                info.releaseNotes,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _launchUrl(info.downloadUrl);
          },
          child: const Text('下载更新'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('稍后再说'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 5: 在关于对话框中添加"检查更新"入口**

修改 `_showAbout` 方法，在版本号显示行之后添加：

```dart
const SizedBox(height: 4),
InkWell(
  onTap: () {
    Navigator.of(ctx).pop();
    _checkForUpdate();
  },
  child: const Text(
    '检查更新',
    style: TextStyle(
      color: Colors.blue,
      fontSize: 13,
      decoration: TextDecoration.underline,
    ),
  ),
),
```

- [ ] **Step 6: 运行分析确认无错误**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 7: 运行测试确认无回归**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: integrate update checker into HomeScreen"
```

---

### Task 4: 最终验证

- [ ] **Step 1: 格式检查**

Run: `dart format --output=none --set-exit-if-changed lib test`
Expected: No formatting issues

- [ ] **Step 2: 全量分析**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 3: 全量测试**

Run: `flutter test`
Expected: All tests PASS

- [ ] **Step 4: Commit（如有格式修复）**

```bash
git add -A
git commit -m "style: fix formatting for update checker"
```
