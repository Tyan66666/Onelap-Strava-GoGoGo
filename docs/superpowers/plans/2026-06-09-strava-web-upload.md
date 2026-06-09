# Strava 网页上传功能实现计划

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 WanSync 添加 Strava 网页上传模式，作为 API 模式的备选方案（2026年7月 Strava API 将需要会员）

**Architecture:** 新增 `StravaWebClient` HTTP 客户端 + `StravaWebSyncAdapter` 适配器，通过设置中的上传方式切换。WebView 登录获取 cookies，Dio 携带 cookies 上传到 `/upload/files`。

**Tech Stack:** Flutter/Dart, Dio, webview_flutter, flutter_secure_storage

**Spec:** `docs/superpowers/specs/2026-06-09-strava-web-upload-design.md`

---

## 文件结构

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/services/strava_web_client.dart` | 创建 | 网页上传 HTTP 客户端 + 异常类 |
| `lib/services/strava_web_sync_adapter.dart` | 创建 | 同步流程适配器 |
| `lib/services/strava_upload_client.dart` | 创建 | 共享上传接口 |
| `lib/screens/strava_web_login_screen.dart` | 创建 | WebView 登录页面 |
| `lib/services/settings_service.dart` | 修改 | 新增设置键 |
| `lib/screens/settings_screen.dart` | 修改 | 上传方式选择 UI |
| `lib/screens/home_screen.dart` | 修改 | 根据模式选择客户端 |
| `lib/services/sync_engine.dart` | 修改 | 适配网页模式 |
| `lib/services/strava_fit_uploader.dart` | 修改 | 分享流程工厂分支 |
| `lib/services/fit_upload_coordinator.dart` | 修改 | 配置检查分支 |
| `test/services/strava_web_client_test.dart` | 创建 | 单元测试 |

---

### Task 1: SettingsService — 新增设置键

**Files:**
- Modify: `lib/services/settings_service.dart`
- Test: `test/services/settings_service_test.dart`（如存在）

- [ ] **Step 1: 新增设置键常量**

在 `SettingsService` 类中新增：

```dart
static const keyStravaUploadMode = 'STRAVA_UPLOAD_MODE';
static const keyStravaWebCookies = 'STRAVA_WEB_COOKIES';
```

- [ ] **Step 2: 添加到 allKeys 列表**

在 `allKeys` 列表中添加这两个键。

- [ ] **Step 3: 运行分析**

```bash
flutter analyze lib/services/settings_service.dart
```

- [ ] **Step 4: 提交**

```bash
git add lib/services/settings_service.dart
git commit -m "feat: add Strava web upload settings keys"
```

---

### Task 2: StravaWebClient — 异常类

**Files:**
- Create: `lib/services/strava_web_client.dart`

- [ ] **Step 1: 创建文件并定义异常类**

```dart
import 'dart:io';
import 'package:dio/dio.dart';

class StravaWebSessionExpiredError implements Exception {
  final String message;
  const StravaWebSessionExpiredError([this.message = 'Strava 网页登录已过期']);
  @override
  String toString() => 'StravaWebSessionExpiredError: $message';
}

class StravaWebUploadError implements Exception {
  final String message;
  const StravaWebUploadError(this.message);
  @override
  String toString() => 'StravaWebUploadError: $message';
}
```

- [ ] **Step 2: 运行分析**

```bash
flutter analyze lib/services/strava_web_client.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/strava_web_client.dart
git commit -m "feat: add Strava web upload exception classes"
```

---

### Task 3: StravaWebClient — 核心实现

**Files:**
- Modify: `lib/services/strava_web_client.dart`
- Create: `test/services/strava_web_client_test.dart`

- [ ] **Step 1: 编写 CSRF token 获取测试**

```dart
// test/services/strava_web_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/services/strava_web_client.dart';

void main() {
  group('StravaWebClient', () {
    test('StravaWebSessionExpiredError has correct message', () {
      const e = StravaWebSessionExpiredError();
      expect(e.message, 'Strava 网页登录已过期');
    });

    test('StravaWebUploadError has correct message', () {
      const e = StravaWebUploadError('test error');
      expect(e.message, 'test error');
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

```bash
flutter test test/services/strava_web_client_test.dart
```

- [ ] **Step 3: 实现 StravaWebClient**

在 `strava_web_client.dart` 中添加完整实现：

```dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'strava_client.dart' show StravaRetriableError;

class StravaWebClient {
  static const _uploadUrl = 'https://www.strava.com/upload/files';
  static const _progressUrl = 'https://www.strava.com/upload/progress.json';
  static const _selectUrl = 'https://www.strava.com/upload/select';

  final Dio _dio;

  StravaWebClient({required String cookies})
    : _dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Cookie': cookies},
      ));

  Future<String> _fetchCsrfToken() async {
    final response = await _dio.get(_selectUrl);
    final html = response.data as String;
    final match = RegExp(r'<meta name="csrf-token" content="([^"]+)"').firstMatch(html);
    if (match == null) throw const StravaWebUploadError('无法获取 CSRF token');
    return match.group(1)!;
  }

  Future<bool> isSessionValid() async {
    try {
      final response = await _dio.get(_selectUrl,
        options: Options(followRedirects: false));
      if (response.statusCode == 302) {
        final location = response.headers.value('location') ?? '';
        return !location.contains('/login');
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> uploadFit(File file) async {
    final csrf = await _fetchCsrfToken();
    final formData = FormData.fromMap({
      'files[]': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
      '_method': 'post',
      'authenticity_token': csrf,
    });
    try {
      final response = await _dio.post(_uploadUrl, data: formData);
      final data = (response.data as List).first as Map<String, dynamic>;
      return {
        'upload_id': data['id'],
        'workflow': data['workflow'],
      };
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw StravaRetriableError('Strava 网页上传限流');
      }
      if (e.response?.statusCode == 403) {
        throw const StravaWebSessionExpiredError();
      }
      throw StravaWebUploadError(e.message ?? '上传失败');
    }
  }

  Future<Map<String, dynamic>> pollUpload(int uploadId) async {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final response = await _dio.get('$_progressUrl?ids[]=$uploadId');
        final data = (response.data as List).first as Map<String, dynamic>;
        final workflow = data['workflow'] as String;
        if (workflow == 'complete') {
          return {'activity_id': data['activity_id'] ?? data['id'], 'workflow': 'complete'};
        }
        if (workflow == 'error') {
          return {'error': data['error'] as String? ?? 'Unknown error', 'workflow': 'error'};
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 429) {
          throw StravaRetriableError('Strava 轮询限流');
        }
        rethrow;
      }
    }
    return {'error': '上传超时', 'workflow': 'error'};
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

```bash
flutter test test/services/strava_web_client_test.dart
```

- [ ] **Step 5: 运行分析**

```bash
flutter analyze lib/services/strava_web_client.dart
```

- [ ] **Step 6: 提交**

```bash
git add lib/services/strava_web_client.dart test/services/strava_web_client_test.dart
git commit -m "feat: implement StravaWebClient with upload and polling"
```

---

### Task 4: StravaWebSyncAdapter

**Files:**
- Create: `lib/services/strava_web_sync_adapter.dart`

- [ ] **Step 1: 创建适配器**

```dart
import 'dart:io';
import 'strava_web_client.dart';

class StravaWebSyncAdapter {
  final StravaWebClient _webClient;

  StravaWebSyncAdapter({required String cookies})
    : _webClient = StravaWebClient(cookies: cookies);

  Future<int> uploadFit(File file) async {
    final result = await _webClient.uploadFit(file);
    return result['upload_id'] as int;
  }

  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _webClient.pollUpload(uploadId);
  }

  Future<bool> activityExists(int activityId) async => true;

  Future<void> ensureAccessToken() async {}
}
```

- [ ] **Step 2: 运行分析**

```bash
flutter analyze lib/services/strava_web_sync_adapter.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/strava_web_sync_adapter.dart
git commit -m "feat: add StravaWebSyncAdapter for SyncEngine integration"
```

---

### Task 5: WebView 登录页面

**Files:**
- Create: `lib/screens/strava_web_login_screen.dart`

- [ ] **Step 1: 创建登录页面**

```dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/settings_service.dart';

class StravaWebLoginScreen extends StatefulWidget {
  final void Function(String cookies) onLoginSuccess;

  const StravaWebLoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<StravaWebLoginScreen> createState() => _StravaWebLoginScreenState();
}

class _StravaWebLoginScreenState extends State<StravaWebLoginScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (url) async {
          setState(() => _loading = false);
          if (url.contains('/dashboard') || url.contains('/athlete')) {
            await _extractCookies();
          }
        },
      ))
      ..loadRequest(Uri.parse('https://www.strava.com/login'));
  }

  Future<void> _extractCookies() async {
    final cookies = await WebViewCookieManager().getCookies('https://www.strava.com');
    final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    if (cookieStr.isNotEmpty && mounted) {
      widget.onLoginSuccess(cookieStr);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 Strava')),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 运行分析**

```bash
flutter analyze lib/screens/strava_web_login_screen.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/screens/strava_web_login_screen.dart
git commit -m "feat: add Strava WebView login screen"
```

---

### Task 6: 设置页面 UI — 上传方式选择

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: 添加状态变量**

在 `_SettingsScreenState` 中添加：

```dart
String _stravaUploadMode = 'api';
bool _stravaWebLoggedIn = false;
```

- [ ] **Step 2: 在 initState 中加载状态**

从 settings 读取 `_stravaUploadMode`，检查 `_stravaWebCookies` 是否存在。

- [ ] **Step 3: 在"上传到 Strava"开关下方添加上传方式选择**

使用 `RadioListTile` 或 `SegmentedButton` 实现 API/网页切换。选择网页时显示"登录 Strava"按钮和登录状态。

- [ ] **Step 4: 实现模式切换逻辑**

切换时保留原有凭证，更新 `_stravaUploadMode` 并保存到设置。

- [ ] **Step 5: 运行分析**

```bash
flutter analyze lib/screens/settings_screen.dart
```

- [ ] **Step 6: 提交**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat: add Strava upload mode selector in settings"
```

---

### Task 7: HomeScreen — 网页模式客户端选择

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 读取上传模式**

在 `_sync()` 方法中读取 `keyStravaUploadMode`。

- [ ] **Step 2: 根据模式创建客户端**

网页模式：创建 `StravaWebClient`，检查 session 有效性，用 `StravaWebSyncAdapter` 包装（类型为 `StravaUploadClient`）。
API 模式：保持现有逻辑（`StravaClient` 也实现了 `StravaUploadClient`）。

- [ ] **Step 3: 错误处理**

session 过期时显示 SnackBar 提示用户去设置页面重新登录。

- [ ] **Step 4: 运行分析**

```bash
flutter analyze lib/screens/home_screen.dart
```

- [ ] **Step 5: 提交**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: integrate web upload mode in HomeScreen sync flow"
```

---

### Task 8: SyncEngine — 适配网页模式

**Files:**
- Modify: `lib/services/sync_engine.dart`
- Create: `lib/services/strava_upload_client.dart`（共享接口）

- [ ] **Step 1: 创建共享接口**

```dart
// lib/services/strava_upload_client.dart
import 'dart:io';

abstract class StravaUploadClient {
  Future<int> uploadFit(File file);
  Future<Map<String, dynamic>> pollUpload(int uploadId);
  Future<bool> activityExists(int activityId);
  Future<void> ensureAccessToken();
}
```

- [ ] **Step 2: 让 StravaClient 实现此接口**

在 `strava_client.dart` 中添加 `implements StravaUploadClient`（如果已有相同签名的方法则只需添加 implements 声明）。

- [ ] **Step 3: 让 StravaWebSyncAdapter 实现此接口**

在 `strava_web_sync_adapter.dart` 中添加 `implements StravaUploadClient`。

- [ ] **Step 4: 修改 SyncEngine 构造函数**

将 `StravaClient?` 参数类型改为 `StravaUploadClient?`。

- [ ] **Step 5: 运行分析**

```bash
flutter analyze lib/services/sync_engine.dart lib/services/strava_upload_client.dart
```

- [ ] **Step 6: 运行所有测试**

```bash
flutter test
```

- [ ] **Step 7: 提交**

```bash
git add lib/services/strava_upload_client.dart lib/services/strava_web_sync_adapter.dart lib/services/sync_engine.dart
git commit -m "feat: introduce StravaUploadClient interface for SyncEngine"
```

---

### Task 9: 分享流程 — FitUploadCoordinator 配置检查

**Files:**
- Modify: `lib/services/fit_upload_coordinator.dart`

- [ ] **Step 1: 修改 _hasStravaConfig**

根据上传模式检查不同凭证：API 模式检查 OAuth，网页模式检查 cookies。

- [ ] **Step 2: 运行分析**

```bash
flutter analyze lib/services/fit_upload_coordinator.dart
```

- [ ] **Step 3: 提交**

```bash
git add lib/services/fit_upload_coordinator.dart
git commit -m "feat: support web mode in FitUploadCoordinator config check"
```

---

### Task 10: 分享流程 — StravaFitUploader 工厂分支

**Files:**
- Modify: `lib/services/strava_fit_uploader.dart`

- [ ] **Step 1: 修改默认工厂函数**

根据上传模式选择创建 `StravaClient` 或 `StravaWebClientAdapter`。

- [ ] **Step 2: 创建 StravaWebClientAdapter**

实现 `StravaFitUploadClient` 接口，包装 `StravaWebClient`。

- [ ] **Step 3: 运行分析**

```bash
flutter analyze lib/services/strava_fit_uploader.dart
```

- [ ] **Step 4: 提交**

```bash
git add lib/services/strava_fit_uploader.dart
git commit -m "feat: add web upload factory branch in StravaFitUploader"
```

---

### Task 11: 集成测试 — 端到端验证

- [ ] **Step 1: 运行所有现有测试**

```bash
flutter test
```

确认没有回归。

- [ ] **Step 2: 运行分析**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
```

- [ ] **Step 3: 手动测试**

1. 设置页面：切换上传方式，验证 UI 更新
2. 网页登录：点击"登录 Strava"，完成登录，验证 cookies 保存
3. 同步流程：选择网页模式，点击同步，验证上传成功
4. 分享流程：分享 FIT 文件到 App，验证网页模式上传

- [ ] **Step 4: 最终提交**

```bash
git add lib/services/strava_web_client.dart lib/services/strava_web_sync_adapter.dart \
  lib/services/strava_upload_client.dart lib/screens/strava_web_login_screen.dart \
  lib/services/settings_service.dart lib/screens/settings_screen.dart \
  lib/screens/home_screen.dart lib/services/sync_engine.dart \
  lib/services/strava_fit_uploader.dart lib/services/fit_upload_coordinator.dart \
  test/services/strava_web_client_test.dart
git commit -m "feat: complete Strava web upload feature"
```
