# Intervals.icu 同步功能设计

## 概述

新增 Intervals.icu 作为第三个同步目标平台，与 Strava、行者并列。同时重构设置页面，将各平台设置拆分为独立子页面。

## 目标

1. 支持将 OneLap 活动的 FIT 文件上传到 Intervals.icu
2. 支持两种上传场景：批量同步（SyncEngine）和单文件分享上传（FitUploadCoordinator）
3. 重构设置页面，解决平台增多后页面过长的问题
4. 修复 UI 中"已通过"文案，改为"已跳过"

## 非目标

- 不支持从 Intervals.icu 拉取数据（仅上传方向）
- 不抽象通用平台接口（各平台差异大，统一接口收益低）
- 不支持 Intervals.icu 的额外上传参数（name、description 等），由服务端自动解析 FIT 文件

## 设计方案

### 1. IntervalsIcuClient

新建 `lib/services/intervals_icu_client.dart`。

```dart
class IntervalsIcuClient {
  final Dio _dio;
  final String athleteId;
  final String apiKey;

  Future<int> uploadFit(File file) async {
    // POST /api/v1/athlete/{athleteId}/activities
    // Content-Type: multipart/form-data
    // Auth: Basic Auth ("API_KEY", apiKey)
    // Returns activity ID on success
  }
}
```

**认证**: HTTP Basic Auth，用户名固定为 `API_KEY`，密码为用户的 API Key。

**上传端点**: `POST /api/v1/athlete/{athleteId}/activities`
- 请求体: `multipart/form-data`，字段名 `file`
- 响应: 201 表示新活动创建成功，200 表示重复文件（视为成功）
- 无需轮询，同步返回结果

**错误处理**:
- 401 → `IntervalsIcuPermanentError`（API Key 无效）
- 429/5xx → `IntervalsIcuRetriableError`（限流或服务端错误）
- 其他 4xx → `IntervalsIcuPermanentError`

**Dio 配置**:
- 超时: 30s connect / 30s receive（与项目其他 client 一致）
- 响应类型: `ResponseType.json`

### 2. Settings 页面重构

#### 主设置页 (`SettingsScreen`)

保留以下内容:
- OneLap 账号区块（用户名、密码、登录验证）
- 同步设置区块（GCJ 坐标纠偏开关、回看天数）

新增**同步平台**区块，包含三张平台卡片:
- Strava — 显示启用状态，点击进入 `StravaSettingsScreen`
- 行者 — 显示启用状态，点击进入 `XingzheSettingsScreen`
- Intervals.icu — 显示启用状态，点击进入 `IntervalsIcuSettingsScreen`

每张卡片布局: `[平台图标] [平台名称] [启用开关] [>]`

#### 平台子页面

**`StravaSettingsScreen`** — 从现有 SettingsScreen 提取:
- 上传模式选择（API / Web）
- API 模式: OAuth 授权流程
- Web 模式: WebView 登录

**`XingzheSettingsScreen`** — 从现有 SettingsScreen 提取:
- 用户名、密码输入
- 登录验证

**`IntervalsIcuSettingsScreen`** — 新建:
- Athlete ID 输入框（提示格式: i12345）
- API Key 输入框（密码模式）
- 简要说明: "在 Intervals.icu 设置 > Developer 中生成 API Key"

### 3. SyncEngine 集成

修改 `lib/services/sync_engine.dart`:

- 构造函数新增参数: `IntervalsIcuClient? intervalsIcuClient`, `bool uploadToIntervalsIcu = false`
- 新增 `_uploadToIntervalsIcu()` helper 方法，结构与 `_uploadToStrava()` / `_uploadToXingzhe()` 一致
- Phase 5 并行上传: `Future.wait()` 中新增 Intervals.icu 上传任务
- 三平台互不影响，任一失败不取消其他平台

### 4. FitUploadCoordinator 集成

修改 `lib/services/fit_upload_coordinator.dart`:

- 新增 `IntervalsIcuUploader` 实现 `FitPlatformUploader` 接口
- `FitPlatformUploader` 接口新增 `intervalsIcu` 枚举值
- 构造函数接收 `IntervalsIcuClient?`

### 5. Model 更新

#### SyncRecord (`lib/models/sync_record.dart`)
- `SyncPlatform` 枚举新增 `intervalsIcu`
- `PlatformSyncResult` 的 platform 字段使用枚举

#### SyncProgress (`lib/models/sync_progress.dart`)
- 新增 `intervalsIcuUploaded`、`intervalsIcuTotal` 字段
- `copyWith()` 同步更新

#### SyncSummary (`lib/models/sync_summary.dart`)
- 新增 `intervalsIcuSuccess`、`intervalsIcuFailed`、`intervalsIcuDeduped`、`intervalsIcuFailures` 字段

#### SyncResultBanner (`lib/models/sync_result_banner.dart`)
- 从 SyncSummary 构建时包含 Intervals.icu 数据
- UI 展示新增 Intervals.icu 芯片

### 6. StateStore 更新

修改 `lib/services/state_store.dart`:
- `'intervals_icu'` 作为新的平台字符串
- `markPlatformSynced()` / `getPlatformSyncStatus()` 支持新平台
- `state.json` 结构兼容，新增平台不影响已有数据

### 7. UI 更新

#### 同步进度对话框
- 新增第三条进度条: Intervals.icu 上传进度
- 三个平台并列显示

#### 同步结果横幅
- 新增 Intervals.icu 芯片（成功/失败/跳过数量）

#### 文案修复
- 所有"已通过"改为"已跳过"

## 文件清单

| 操作 | 文件 | 说明 |
|------|------|------|
| 新建 | `lib/services/intervals_icu_client.dart` | Intervals.icu API 客户端 |
| 新建 | `lib/screens/intervals_icu_settings_screen.dart` | Intervals.icu 设置页面 |
| 新建 | `lib/screens/strava_settings_screen.dart` | Strava 设置页面（从现有设置页提取） |
| 新建 | `lib/screens/xingzhe_settings_screen.dart` | 行者设置页面（从现有设置页提取） |
| 修改 | `lib/screens/settings_screen.dart` | 重构为主页面 + 平台卡片列表 |
| 修改 | `lib/services/sync_engine.dart` | 新增 Intervals.icu 上传逻辑 |
| 修改 | `lib/services/fit_upload_coordinator.dart` | 新增 IntervalsIcuUploader |
| 修改 | `lib/services/settings_service.dart` | 新增 INTERVALS_ICU_ATHLETE_ID、INTERVALS_ICU_API_KEY |
| 修改 | `lib/services/state_store.dart` | 支持 intervals_icu 平台 |
| 修改 | `lib/models/sync_record.dart` | 枚举新增 intervalsIcu |
| 修改 | `lib/models/sync_progress.dart` | 新增 intervalsIcu 字段 |
| 修改 | `lib/models/sync_summary.dart` | 新增 intervalsIcu 字段 |
| 修改 | `lib/models/sync_result_banner.dart` | 新增 intervalsIcu 数据 |
| 修改 | `lib/screens/home_screen.dart` | 进度条 + 结果横幅 + 文案修复 |

## 去重策略

复用现有两层去重机制:
1. **dedupeKey**: `"{startTime}_{distanceM}_{timeSeconds}"` — 活动级别去重
2. **fingerprint**: `"{recordKey}|{SHA256 of FIT bytes}|{startTime}"` — 文件级别去重

Intervals.icu 作为新平台，状态存储在 `state.json` 的 `synced[fingerprint].platforms.intervals_icu` 中。

## 错误处理

遵循现有模式:
- `IntervalsIcuRetriableError` — 429、5xx，下次同步自动重试
- `IntervalsIcuPermanentError` — 401、其他 4xx，需要用户修复配置
- 上传 helper 内部 catch 所有异常，不向外传播

## 测试

- `test/services/intervals_icu_client_test.dart` — Client 单元测试（mock Dio）
- `test/models/` — 各 model 的序列化/反序列化测试更新
- 集成测试: 手动验证同步流程 + 设置页面导航
