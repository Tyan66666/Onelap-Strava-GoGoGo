# Strava 网页上传功能设计

## 背景

Strava 将于 2026 年 7 月对非会员用户限制 API 访问。为确保非会员用户仍能同步活动到 Strava，新增"网页上传"模式作为 API 的备选方案。

## 目标

- 在设置中新增 Strava 上传方式选择：API（默认）/ 网页
- 网页上传模式通过 WebView 登录 + HTTP 上传实现，不依赖 Strava API
- 两种模式完全独立，凭证互不干扰，切换时保留各自的配置
- 现有的去重、状态持久化、同步历史等功能在两种模式下行为一致

## 架构概览

```
┌─────────────────────────────────────────────────────────┐
│                      SyncEngine                          │
│           (根据 stravaUploadMode 选择客户端)              │
├──────────────────────┬──────────────────────────────────┤
│     StravaClient     │       StravaWebClient            │
│     (API 模式)        │       (网页上传模式)              │
│     OAuth token      │       Session cookies + CSRF     │
│     /api/v3/uploads  │       /upload/files              │
└──────────────────────┴──────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                  FitUploadCoordinator                     │
│             (分享 FIT 文件上传，同理选择客户端)             │
├──────────────────────┬──────────────────────────────────┤
│   StravaFitUploader  │  StravaWebClientAdapter          │
│   (API 模式)          │  (网页上传模式，包装 Web客户端)    │
└──────────────────────┴──────────────────────────────────┘
```

同步流程和分享流程都通过统一的 `StravaUploader` 接口选择客户端，逻辑一致。

## 新增文件

| 文件 | 说明 |
|------|------|
| `lib/services/strava_web_client.dart` | 网页上传 HTTP 客户端 + `StravaWebSessionExpiredError` + `StravaWebUploadError` |
| `lib/services/strava_web_sync_adapter.dart` | 同步流程适配器，包装 `StravaWebClient` 匹配 `StravaClient` 方法签名 |
| `lib/screens/strava_web_login_screen.dart` | WebView 登录页面 |

## 修改文件

| 文件 | 变更 |
|------|------|
| `lib/services/settings_service.dart` | 新增 `keyStravaUploadMode`、`keyStravaWebCookies` |
| `lib/screens/settings_screen.dart` | 新增上传方式选择 UI + 网页登录按钮 + 提示文案 |
| `lib/screens/home_screen.dart` | 根据模式选择客户端，网页模式下检查 session 有效性 |
| `lib/services/sync_engine.dart` | 适配统一上传接口 |
| `lib/services/strava_fit_uploader.dart` | 新增网页上传客户端工厂分支 |
| `lib/services/fit_upload_coordinator.dart` | 根据设置选择 API 或网页上传器 |

---

## StravaWebClient

```dart
class StravaWebClient {
  static const _uploadUrl = 'https://www.strava.com/upload/files';
  static const _progressUrl = 'https://www.strava.com/upload/progress.json';
  static const _selectUrl = 'https://www.strava.com/upload/select';

  final Dio _dio;  // 携带 cookies 的 HTTP 客户端，30s 超时

  StravaWebClient({required String cookies});

  // 返回 Map<String, dynamic> 与现有 StravaClient 接口一致
  // 成功: {"activity_id": 123456}
  // 失败: {"error": "错误信息"}
  Future<Map<String, dynamic>> uploadFit(File file);
  Future<Map<String, dynamic>> pollUpload(int uploadId);
  Future<bool> activityExists(int activityId);  // 始终返回 true
  Future<bool> isSessionValid();

  Future<String> _fetchCsrfToken();
}
```

### 返回值格式

`uploadFit()` 和 `pollUpload()` 返回 `Map<String, dynamic>`，与现有 `StravaClient` 一致：

```dart
// 上传成功
{"upload_id": 19959228318, "workflow": "new"}

// 轮询成功
{"activity_id": 123456, "workflow": "complete"}

// 轮询失败
{"error": "The upload appears to be malformed...", "workflow": "error"}

// 重复上传（与 _isIdempotentSuccess 兼容）
{"error": "duplicate of activity 123456", "workflow": "error"}
```

### 上传流程

1. GET `/upload/select` → 从 `<meta name="csrf-token">` 提取 CSRF token
2. POST `/upload/files`（multipart/form-data）
   - `files[]` = FIT 文件
   - `_method` = `"post"`
   - `authenticity_token` = CSRF token
3. 响应：`[{"id": <uploadId>, "workflow": "new", ...}]`
4. GET `/upload/progress.json?ids[]=<uploadId>` 轮询（每 2 秒，最多 10 次）
5. 完成条件：`workflow` 变为 `"complete"`、`"done"`、`"success"` 或 `"error"`

### 错误处理

| 情况 | 异常类型 | 处理 |
|------|----------|------|
| HTTP 403 / 重定向到登录页 | `StravaWebSessionExpiredError` | session 过期，上层提示用户重新登录 |
| HTTP 429 | `StravaRetriableError` | 限流，上层可重试 |
| 轮询 `workflow: "error"` | `StravaWebUploadError` | 包含错误信息，上层显示给用户 |
| 其他网络错误 | `StravaWebUploadError` | 抛出异常，由上层处理 |

### 异常类定义

```dart
class StravaWebSessionExpiredError implements Exception {
  final String message;
  const StravaWebSessionExpiredError([this.message = 'Strava 网页登录已过期']);
}

class StravaWebUploadError implements Exception {
  final String message;
  const StravaWebUploadError(this.message);
}
```

### Session 有效性检查

`isSessionValid()` 访问 `/upload/select`，检查是否被重定向到 `/login`。如果重定向则 session 已过期。

### 重复上传处理

网页上传的轮询响应中，`error` 字段可能包含 "duplicate of activity XXXXX" 格式的消息。`StravaWebClient` 将此原样返回，由 `SyncEngine._isIdempotentSuccess()` 统一处理（该方法已识别 "duplicate" 关键字）。

---

## WebView 登录页面

`StravaWebLoginScreen` 负责用户登录和 cookies 提取。

### 流程

1. 打开 WebView 加载 `https://www.strava.com/login`
2. 用户手动登录（邮箱/密码 或 Google/Apple 登录）
3. 登录成功后 WebView 跳转到 `https://www.strava.com/dashboard`
4. 从 WebView cookie manager 提取所有 Strava 域名的 cookies
5. 序列化为字符串，回调 `onLoginSuccess`
6. 保存到 `SettingsService.keyStravaWebCookies`

### Cookie 序列化格式

```
key1=value1; key2=value2; key3=value3
```

标准 HTTP Cookie header 格式，Dio 可直接使用。

### Cookie 提取注意事项

- 使用 `webview_flutter` 的 `CookieManager.getCookies(url)` 提取 cookies
- `HttpOnly` cookies 可以通过 `CookieManager` 获取（WebView 有完整访问权限）
- cookies 存储在 `flutter_secure_storage` 中，即使 App 退出也持久化
- `isSessionValid()` 是权威检查：cookies 字符串非空只是前提条件，实际有效性通过访问 `/upload/select` 验证
- 如果 cookies 过期，`isSessionValid()` 返回 `false`，上层提示用户重新登录

### Google/Apple SSO 注意事项

- Google/Apple 登录可能打开弹窗或重定向多个域名，`webview_flutter` 可能无法正确处理弹窗
- 如果 SSO 登录失败，建议用户使用邮箱/密码方式登录
- 后续可考虑使用 `url_launcher` 打开系统浏览器完成 SSO，再回调 App

---

## 统一上传接口

`SyncEngine` 中的 Strava 上传有两个调用点，使用不同的抽象层：

### 同步流程接口（SyncEngine 使用）

```dart
// SyncEngine 直接调用 StravaClient 的方法，不通过抽象接口
// 网页模式需要一个适配器来匹配 StravaClient 的方法签名
class StravaWebSyncAdapter {
  final StravaWebClient _webClient;
  StravaWebSyncAdapter({required String cookies})
    : _webClient = StravaWebClient(cookies: cookies);

  // 匹配 StravaClient.uploadFit() 签名：返回 int (uploadId)
  Future<int> uploadFit(File file) async {
    final result = await _webClient.uploadFit(file);
    return result['upload_id'] as int;
  }

  // 匹配 StravaClient.pollUpload() 签名：返回 Map<String, dynamic>
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _webClient.pollUpload(uploadId);
  }

  // 匹配 StravaClient.activityExists() 签名
  Future<bool> activityExists(int activityId) async => true;

  // 匹配 StravaClient.ensureAccessToken() 签名（空操作）
  Future<void> ensureAccessToken() async {}
}
```

### 分享流程接口（FitUploadCoordinator 使用）

```dart
// StravaFitUploadClient 接口（现有）
abstract class StravaFitUploadClient {
  Future<int> uploadFit(File file);  // 返回 uploadId
}

// StravaWebClientAdapter 实现此接口
class StravaWebClientAdapter implements StravaFitUploadClient {
  final StravaWebClient _webClient;
  StravaWebClientAdapter({required String cookies})
    : _webClient = StravaWebClient(cookies: cookies);

  @override
  Future<int> uploadFit(File file) async {
    final result = await _webClient.uploadFit(file);
    return result['upload_id'] as int;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _webClient.pollUpload(uploadId);
  }
}
```

`StravaWebClient` 是底层 HTTP 客户端，两个适配器分别包装它以匹配不同调用方的接口。

---

## 设置页面 UI

### 上传设置区域布局

```
┌─────────────────────────────────────┐
│  上传设置                            │
│  ┌─────────────────────────────┐    │
│  │ 上传到 Strava          [开] │    │
│  ├─────────────────────────────┤    │
│  │ 上传方式:  ○ API  ○ 网页    │    │  ← 新增
│  │                             │    │
│  │ ℹ️ 推荐使用 API 方式，最稳定  │    │  ← 提示
│  │    2026年7月起需要 Strava 会员│    │
│  ├─────────────────────────────┤    │
│  │ (选择 API 时显示)           │    │
│  │ ┌───────────────────────┐   │    │
│  │ │ Strava OAuth 配置区域  │   │    │
│  │ │ Client ID / Secret    │   │    │
│  │ │ [授权 Strava] 按钮     │   │    │
│  │ └───────────────────────┘   │    │
│  │                             │    │
│  │ (选择 网页 时显示)          │    │
│  │ ┌───────────────────────┐   │    │
│  │ │ [登录 Strava] 按钮     │   │    │
│  │ │ 状态: ✅ 已登录 / ❌未登录│   │    │
│  │ └───────────────────────┘   │    │
│  ├─────────────────────────────┤    │
│  │ 上传到 行者            [关] │    │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### 提示文案

- 默认选中 API 模式
- API 选项旁显示"推荐"标签
- 网页选项旁显示"2026年7月后备选"标签
- 在选择器下方显示提示："推荐使用 API 方式，最稳定。2026 年 7 月起 Strava API 将需要会员订阅，届时可切换到网页上传。"

### 模式切换行为

- API → 网页：OAuth 凭证保留在设置中，不清除
- 网页 → API：cookies 保留在设置中，不清除
- 两种模式的凭证互不干扰

### 网页模式状态显示

- 已登录（cookies 存在且 session 有效）：显示绿色"已登录"
- 未登录 / session 过期：显示红色"未登录"，提示用户点击"登录 Strava"

---

## 同步流程集成

### HomeScreen 修改

```dart
final stravaMode = settings.read(SettingsService.keyStravaUploadMode) ?? 'api';

if (uploadToStrava) {
  if (stravaMode == 'web') {
    final cookies = settings.read(SettingsService.keyStravaWebCookies);
    if (cookies == null || cookies.isEmpty) {
      // 提示用户需要先登录 Strava
      return;
    }
    final webClient = StravaWebClient(cookies: cookies);
    if (!await webClient.isSessionValid()) {
      // 提示 session 过期，需要重新登录
      return;
    }
    // 使用适配器包装，匹配 SyncEngine 期望的接口
    stravaClient = StravaWebSyncAdapter(cookies: cookies) as dynamic;
  } else {
    stravaClient = StravaClient(...);  // 现有逻辑
  }
}
```

### SyncEngine 修改

- SyncEngine 继续使用 `StravaClient?` 类型（或引入共同接口）
- 网页模式下传入 `StravaWebSyncAdapter`，它实现了与 `StravaClient` 相同的方法签名
- 上传逻辑不变，调用 `uploadFit()` 和 `pollUpload()`
- 去重逻辑不变，fingerprint 和 dedupeKey 共享同一个 state.json
- `activityExists()` 在网页模式下始终返回 `true`（跳过 API 验证）

---

## 设置持久化

### 新增键

| 键名 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `STRAVA_UPLOAD_MODE` | String | `"api"` | 上传模式：`"api"` 或 `"web"` |
| `STRAVA_WEB_COOKIES` | String | `""` | 序列化的 cookies 字符串 |

存储位置：`flutter_secure_storage`（与现有凭证一致）

### state.json 不变

- 现有的 `synced`、`dedupeKeys`、`history`、`banners` 结构完全不变
- 网页上传的活动同样记录 fingerprint 和 dedupeKey
- 两种模式共享同一个 state.json，去重逻辑一致

### 注意事项

- 新增的键需要添加到 `SettingsService.allKeys` 列表中，否则 `loadSettings()` 不会加载它们
- GCJ-02 → WGS84 坐标转换在上传前执行，适用于两种模式（`StravaWebClient` 接收的 File 已经是转换后的）

---

## 分享 FIT 文件流程集成

当用户从其他 App（如 OneLap）分享 `.fit` 文件到顽爪爪时，也需要支持网页上传模式。

### 现有流程

```
ShareIntent → ShareIntakeService → ShareNavigationCoordinator
  → ShareConfirmScreen (用户确认)
    → SharedFitUploadService
      → FitUploadCoordinator
        → StravaFitUploader (API) + XingzheFitUploader
```

### 变更点

**`FitUploadCoordinator._hasRequiredConfiguration`** 需要根据上传模式判断配置是否完整：

```dart
// 现有：只检查 OAuth 凭证
bool _hasStravaConfig(Map<String, String> settings) {
  return settings[keyStravaClientId]?.isNotEmpty == true
      && settings[keyStravaClientSecret]?.isNotEmpty == true
      && settings[keyStravaRefreshToken]?.isNotEmpty == true;
}

// 变更：根据模式检查不同凭证
bool _hasStravaConfig(Map<String, String> settings) {
  final mode = settings[keyStravaUploadMode] ?? 'api';
  if (mode == 'web') {
    return settings[keyStravaWebCookies]?.isNotEmpty == true;
  }
  return settings[keyStravaClientId]?.isNotEmpty == true
      && settings[keyStravaClientSecret]?.isNotEmpty == true
      && settings[keyStravaRefreshToken]?.isNotEmpty == true;
}
```

**`StravaFitUploader`** 的客户端工厂需要根据设置选择创建方式：

```dart
// 现有：只创建 API 客户端
StravaFitUploadClientFactory defaultFactory = (settings) {
  return StravaClient(
    clientId: settings[keyStravaClientId],
    clientSecret: settings[keyStravaClientSecret],
    ...
  );
};

// 变更：根据上传模式选择客户端
StravaFitUploadClientFactory defaultFactory = (settings) {
  final mode = settings[keyStravaUploadMode] ?? 'api';
  if (mode == 'web') {
    final cookies = settings[keyStravaWebCookies];
    if (cookies == null || cookies.isEmpty) {
      throw Exception('Strava 网页未登录，请先在设置中登录');
    }
    return StravaWebClientAdapter(cookies: cookies);
  }
  return StravaClient(...);  // 原有逻辑
};
```

**`StravaWebClientAdapter`** 实现 `StravaFitUploadClient` 接口，包装 `StravaWebClient`：

```dart
class StravaWebClientAdapter implements StravaFitUploadClient {
  final StravaWebClient _webClient;
  StravaWebClientAdapter({required String cookies})
    : _webClient = StravaWebClient(cookies: cookies);

  @override
  Future<int> uploadFit(File file) async {
    final result = await _webClient.uploadFit(file);
    return result['upload_id'] as int;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _webClient.pollUpload(uploadId);
  }
}
```

### 分享流程中的错误处理

| 情况 | 处理 |
|------|------|
| 网页未登录 | `FitUploadCoordinator` 返回 `missingConfiguration`，提示用户去设置页面登录 |
| Session 过期 | `StravaWebClient` 抛出 `StravaWebSessionExpiredError`，`FitUploadCoordinator` 捕获并返回 `failure`，提示"Strava 网页登录已过期，请重新登录" |
| 上传失败 | 与其他平台一致，返回 `failure` 并显示错误信息 |

### 分享流程 UI 不变

`ShareConfirmScreen` 的状态机和 UI 逻辑不需要修改。它已经处理了 `missingConfiguration`、`failure`、`success` 等状态，网页上传的错误会自然映射到这些状态。

---

## 测试要点

1. **设置 UI**：切换上传方式时 UI 正确更新，OAuth 凭证和 cookies 互不影响
2. **WebView 登录**：登录成功后 cookies 正确提取和保存
3. **网页上传（同步流程）**：文件上传成功，轮询返回正确结果
4. **网页上传（分享流程）**：分享 FIT 文件到顽爪爪，网页模式下上传成功
5. **Session 过期**：检测到过期后提示用户重新登录（同步流程和分享流程都要测试）
6. **去重一致性**：API 上传过的活动，网页模式下不会重复上传
7. **错误处理**：网络错误、限流、文件格式错误等情况正确处理
8. **分享流程未登录**：网页模式下分享 FIT 文件但未登录 Strava，显示 `missingConfiguration` 提示
