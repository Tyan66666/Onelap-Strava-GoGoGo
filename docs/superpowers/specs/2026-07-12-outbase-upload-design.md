# Outbase 上传平台集成设计

## 概述

为 WanSync 添加 Outbase 作为新的 FIT 文件上传平台，与 Strava、行者、Intervals.icu 并列。

## 背景

Outbase（https://outbase.cn）是一个运动数据平台，支持批量导入 .fit 格式运动记录。用户希望将 OneLap 的活动自动同步到 Outbase。

### Outbase 上传流程（从浏览器抓包分析）

1. **登录**: 手机号 + 短信验证码 + 极验 CAPTCHA，登录后获得 `sessionId` cookie（有效期 14 天）
2. **CDN 上传**: `POST https://melon-gateway.immomo.com/zeusfit/resource/upload?source=zeusfit&id={guid}{date}&uri=/resource/{prefix}/{guid}{date}.fit&momoid=0&`
   - Body: `FormData(file)`
   - 认证: 无需认证（CDN 端点不校验 session）
   - 响应: `{message: "SUCCESS", data: {...}}`
   - ⚠️ `uri` 中文件名必须包含 dateTag，否则 CDN 返回 "meta.uri is illegal"
3. **API 注册**: `POST https://melon-gateway.immomo.com/zeusfit/api/h5/sport/upload/fit`
   - Body: `{fitGuid, sign (MD5 hex of file bytes), fileName, fileSize}`
   - 认证: 自定义 header `sessionid: {sessionId}` + `uagent: ...PCAgent/1.0.0`（通过浏览器抓包确认）
   - ⚠️ `uagent` 值必须包含 `PCAgent/1.0.0`，否则服务器返回 "Please log in"
   - 响应: `{ec: 0, em: "", data: {...}}`（成功）或 `{ec: 非0, em: "错误消息"}`
4. **去重机制**: ec == 503 或消息包含 "相同时间内已存在其他运动数据" / "已存在" / "请勿重复上传" —— Outbase 有自己的时间段去重

### fitGuid 生成

从抓包分析，`fitGuid` 格式为 UUID v4（带连字符），例如 `d636b65d-aee0-4211-9102-70a3eacbba07`。CDN 上传 URL 中的 `id` 为 `fitGuid + 日期标签`（如 `d636b65d-aee0-4211-9102-70a3eacbba0720260715`），`uri` 中的前缀为 fitGuid 去掉连字符后前 4 个 hex 字符拆成两段（如 `/resource/d6/36/...`）。

### sign 计算

`sign` 为文件内容的 MD5 十六进制摘要（32 字符小写 hex）。

## 设计

### 架构

遵循现有平台集成模式，新增以下组件：

- `OutbaseClient` — 封装 Outbase API（CDN 上传 + API 注册）
- `OutbaseFitUploader` — 实现 `FitPlatformUploader` 接口
- `OutbaseSettingsScreen` — WebView 登录 + 设置页面

### 登录流程

```
用户点击 "Outbase" 设置卡片
  → 打开 OutbaseSettingsScreen
  → 如果未登录，显示 WebView 加载 Outbase 登录页
  → 用户在 WebView 中输入手机号 + 验证码登录
  → 登录成功后（检测 URL 包含 dashboard.html 或 document.cookie 包含 sessionId，OR 逻辑）
  → 注入 JS 读取 document.cookie
  → 从 cookie 中提取 sessionId 并保存到 flutter_secure_storage
  → 记录登录时间到 OUTBASE_LOGIN_TIME
  → 显示登录状态和上次登录时间
```

**sessionId 提取方式**: JS 注入（`document.cookie`）。从抓包分析，Outbase 使用 `Cookies.set("sessionId", ...)` 设置 cookie，说明它不是 httpOnly，JS 可读。

**sessionId 过期处理**: 上传时如果 API 返回 401 或响应体中包含 `log in`/`登录`/`session` 关键词，标记为 `failure` 并提示用户重新登录。UI 上显示上次登录时间，接近 14 天时显示过期警告。

### 上传流程

```
FitUploadCoordinator 收到上传请求
  → 检查 settings 中 UPLOAD_TO_OUTBASE == 'true'
  → 检查 OUTBASE_SESSION_ID 是否存在
  → 调用 OutbaseFitUploader.upload(file, settings)
    → Step 1: POST CDN 上传 (FormData with file)
    → Step 2: POST API 注册 (JSON with fitGuid, sign, fileName, fileSize)
    → 两步都封装在 uploadFit() 方法中，对外透明
  → 返回 FitUploadPlatformResult
```

### 去重处理

- Outbase 返回 "相同时间内已存在其他运动数据" → 视为 `alreadyUploaded`
- Outbase 返回 ec == 0 → 视为 `success`
- 其他错误消息 → 视为 `failure`

### 数据模型变更

#### FitUploadPlatform 枚举

```dart
enum FitUploadPlatform { strava, xingzhe, intervalsIcu, outbase }
```

#### SyncPlatform 枚举

```dart
enum SyncPlatform { strava, xingzhe, intervalsIcu, outbase }
```

#### SyncRecord 模型

新增字段：
- `uploadedToOutbase: bool` — 是否上传到 Outbase

`mergeWith()` 方法需要添加 `uploadedToOutbase` 的 OR 合并逻辑。

#### SyncProgress 模型

新增字段：
- `outbaseUploaded: int` — Outbase 已上传数
- `outbaseEnabled: bool` — Outbase 是否启用

#### SyncSummary 模型

新增字段：
- `outbaseSuccess: int`
- `outbaseFailed: int`
- `outbaseDeduped: int`
- `outbaseFailures: List<FailedActivitySummary>`

### 设置项

| Key | 类型 | 说明 |
|-----|------|------|
| `UPLOAD_TO_OUTBASE` | `bool` | 是否启用 Outbase 上传 |
| `OUTBASE_SESSION_ID` | `string` | Outbase 登录 sessionId |
| `OUTBASE_LOGIN_TIME` | `string` | 上次登录时间（ISO 8601） |

需要添加到 `SettingsService.allKeys` 列表中。

### API 客户端

#### OutbaseClient

```dart
class OutbaseClient {
  OutbaseClient({required this.sessionId, Dio? dio});
  
  final String sessionId;
  
  /// 上传 FIT 文件到 Outbase（包含 CDN 上传 + API 注册两步）
  Future<OutbaseUploadResult> uploadFit(File file);
}

class OutbaseUploadResult {
  final bool success;
  final bool alreadyUploaded;
  final String? message;
}
```

#### 错误类型

- `OutbasePermanentError` — 4xx 错误，不可重试
- `OutbaseRetriableError` — 网络错误或 5xx，可重试

#### OutbaseFitUploader

```dart
class OutbaseFitUploader implements FitPlatformUploader {
  @override
  Future<FitUploadPlatformResult> upload({
    required File file,
    required Map<String, String> settings,
  }) async {
    // 检查 sessionId
    // 调用 OutbaseClient.uploadFit()
    // 处理结果和异常
  }
}
```

### SyncEngine 变更

`SyncEngine` 需要以下修改：

1. **新增字段**:
   - `OutbaseClient? outbaseClient`
   - `bool uploadToOutbase`

2. **新增 `_uploadToOutbase()` 方法**（遵循 `_uploadToStrava` 模式）:
   - 检查 dedup 状态
   - 调用 `outbaseClient.uploadFit()`
   - 处理结果（success/alreadyUploaded/failure）
   - 保存 dedup 状态
   - 返回 `_PlatformUploadResult`

3. **dedup 逻辑**:
   - 在 Phase 2 的 dedup 检查中添加 `skipOutbase` 逻辑
   - 平台字符串使用 `'outbase'`（匹配 `SyncPlatform.outbase.name`）

4. **并行上传**:
   - 在 `uploadFutures` 中添加 Outbase 上传任务
   - 聚合 Outbase 结果到 `outbaseSuccess/Failed/Deduped`

5. **进度追踪**:
   - 更新 `progress.copyWith(outbaseUploaded: ...)`

6. **失败记录**:
   - 在 `_failedRecord()` 中添加 Outbase 平台结果

7. **SyncSummary 构造**:
   - 添加 `outbaseSuccess`, `outbaseFailed`, `outbaseDeduped`, `outbaseFailures`

### FitUploadCoordinator 变更

1. **`_targetLabel()` 方法**: 使用程序化方式生成标签，避免 4 平台的组合爆炸：
   ```dart
   String _targetLabel(List<FitUploadPlatform> targets) {
     final labels = targets.map(_singlePlatformLabel).toList();
     if (labels.length == 1) return labels.first;
     if (labels.length == 2) return '${labels.first} 和${labels.last}';
     return labels.join('、');
   }
   ```

2. **`_hasRequiredConfiguration()` 方法**: 添加 Outbase 检查：
   ```dart
   if (platform == FitUploadPlatform.outbase &&
       !_hasValue(settings, SettingsService.keyOutbaseSessionId)) {
     return false;
   }
   ```

3. **构造函数**: 添加 `OutbaseFitUploader` 参数

### UI

#### OutbaseSettingsScreen

- 显示 WebView 加载 Outbase 登录页
- 监听 URL 变化，登录成功后提取 sessionId
- 显示登录状态（已登录/未登录，上次登录时间）
- 提供重新登录按钮
- 提供退出登录按钮（清除 sessionId）

#### SettingsScreen

在同步平台区域添加 Outbase 卡片：
- Switch 开关控制 `UPLOAD_TO_OUTBASE`
- 点击进入 `OutbaseSettingsScreen`

### state_store.dart

`state_store.dart` 的 `isAlreadyUploaded()` 和 `markPlatformSynced()` 已支持任意平台字符串，无需修改。平台 key 使用 `'outbase'`（匹配 `SyncPlatform.outbase.name`）。

### ConfigService 变更

导出/导入配置时添加 Outbase 部分：
```json
{
  "outbase": {
    "sessionId": "...",
    "uploadToOutbase": true
  }
}
```

导入旧配置（无 `outbase` key）时默认为禁用。

### 错误处理

| 场景 | 处理方式 |
|------|---------|
| sessionId 为空 | 返回 failure，提示用户登录 |
| CDN 上传 4xx | 检查响应体是否为重复上传，是则继续 API 注册，否则抛出 OutbasePermanentError |
| CDN 上传 5xx | 抛出 OutbaseRetriableError |
| CDN 上传网络错误 | 抛出 OutbaseRetriableError |
| API 注册 4xx | 抛出 OutbasePermanentError |
| API 注册 5xx | 抛出 OutbaseRetriableError |
| API 注册网络错误 | 抛出 OutbaseRetriableError |
| API 返回 401 / 响应体含 log in/登录/session | 抛出 OutbasePermanentError，提示用户重新登录 |
| ec == 503 或 "相同时间内已存在其他运动数据" / "已存在" / "请勿重复上传" | 返回 alreadyUploaded |
| ec == 0 | 返回 success |
| 其他错误消息 | 返回 failure |

### 文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/services/outbase_client.dart` | 新建 | API 客户端 |
| `lib/services/outbase_fit_uploader.dart` | 新建 | 平台上传器 |
| `lib/screens/outbase_settings_screen.dart` | 新建 | WebView 登录 + 设置 |
| `lib/services/settings_service.dart` | 修改 | 添加 `keyOutbaseSessionId`, `keyUploadToOutbase`，更新 `allKeys` |
| `lib/services/fit_upload_coordinator.dart` | 修改 | 添加 `outbase` 枚举值，注册上传器，更新 `_targetLabel` 和 `_hasRequiredConfiguration` |
| `lib/models/sync_record.dart` | 修改 | 添加 `SyncPlatform.outbase`, `uploadedToOutbase`，更新 `mergeWith` |
| `lib/models/sync_progress.dart` | 修改 | 添加 `outbaseUploaded`, `outbaseEnabled` |
| `lib/models/sync_summary.dart` | 修改 | 添加 `outbaseSuccess`, `outbaseFailed`, `outbaseDeduped`, `outbaseFailures` |
| `lib/services/shared_fit_upload_service.dart` | 修改 | 添加 Outbase 平台映射 |
| `lib/services/sync_engine.dart` | 修改 | 添加 `uploadToOutbase` 逻辑，`_uploadToOutbase()` 方法，dedup，进度，汇总 |
| `lib/screens/settings_screen.dart` | 修改 | 添加 Outbase 平台卡片 |
| `lib/services/config_service.dart` | 修改 | 导出/导入 Outbase 配置 |
| `lib/screens/home_screen.dart` | 修改 | 显示 Outbase 同步状态（如有） |

### 依赖

- `dio` — HTTP 客户端（已有）
- `crypto` — MD5 计算（已有）
- `webview_flutter` — WebView（已有，用于 Strava OAuth）
- `flutter_secure_storage` — 安全存储（已有）

### 测试策略

- `outbase_client.dart` — 单元测试，mock Dio，覆盖：
  - CDN 上传成功
  - API 注册成功
  - "相同时间内已存在其他运动数据" → alreadyUploaded
  - 4xx 错误 → OutbasePermanentError
  - 5xx/网络错误 → OutbaseRetriableError
- `outbase_fit_uploader.dart` — 单元测试，mock OutbaseClient，覆盖：
  - sessionId 为空 → failure
  - 上传成功 → success
  - 已上传 → alreadyUploaded
  - 异常处理
- 集成测试 — 验证完整上传流程

### 向后兼容性

- `state.json`: `PlatformSyncResult.fromJson` 使用 `SyncPlatform.values.firstWhere(..., orElse: () => SyncPlatform.strava)` 会优雅降级未知平台字符串
- `SyncRecord.fromJson`: 旧版本加载时会忽略 `uploadedToOutbase` 字段（可接受）
- `ConfigService`: 导入旧配置时 `_castMap` 处理缺失 key，默认禁用 Outbase
