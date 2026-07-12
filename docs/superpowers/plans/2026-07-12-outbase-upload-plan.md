# Outbase 上传平台集成 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 WanSync 添加 Outbase 作为新的 FIT 文件上传平台，与 Strava、行者、Intervals.icu 并列。

**Architecture:** 遵循现有平台集成模式，新增 `OutbaseClient`（API 客户端）、`OutbaseFitUploader`（平台上传器）、`OutbaseSettingsScreen`（WebView 登录），并扩展所有相关枚举和模型。

**Tech Stack:** Flutter/Dart, Dio (HTTP), crypto (MD5), webview_flutter (登录), flutter_secure_storage (凭据存储)

**Spec:** `docs/superpowers/specs/2026-07-12-outbase-upload-design.md`

---

### Task 1: 数据模型层 — 枚举和模型扩展

**Files:**
- Modify: `lib/models/sync_record.dart`
- Modify: `lib/models/sync_progress.dart`
- Modify: `lib/models/sync_summary.dart`

- [ ] **Step 1: SyncRecord — 添加 SyncPlatform.outbase 和 uploadedToOutbase**

在 `lib/models/sync_record.dart` 中：

1. `SyncPlatform` 枚举添加 `outbase`
2. `SyncRecord` 类添加 `uploadedToOutbase` 字段（默认 false）
3. `toJson()` 添加 `'uploadedToOutbase': uploadedToOutbase`
4. `fromJson()` 添加 `uploadedToOutbase: json['uploadedToOutbase'] as bool? ?? false`
5. `copyWith()` 添加 `uploadedToOutbase` 参数
6. `mergeWith()` 添加 `uploadedToOutbase: base.uploadedToOutbase || uploadedToOutbase`

- [ ] **Step 2: SyncProgress — 添加 outbase 字段**

在 `lib/models/sync_progress.dart` 中：

1. 添加 `outbaseUploaded` 和 `outbaseEnabled` 字段
2. 更新 `copyWith()`, `==`, `hashCode`, `toString()`

- [ ] **Step 3: SyncSummary — 添加 outbase 字段**

在 `lib/models/sync_summary.dart` 中：

1. 添加 `outbaseSuccess`, `outbaseFailed`, `outbaseDeduped`, `outbaseFailures` 字段
2. 更新构造函数默认值

- [ ] **Step 4: 验证模型变更**

Run: `dart analyze lib/models/`
Expected: 无错误（可能有未使用字段警告，正常）

- [ ] **Step 5: Commit**

```bash
git add lib/models/sync_record.dart lib/models/sync_progress.dart lib/models/sync_summary.dart
git commit -m "feat(models): add Outbase platform to SyncRecord, SyncProgress, SyncSummary"
```

---

### Task 2: 设置层 — SettingsService

**Files:**
- Modify: `lib/services/settings_service.dart`

- [ ] **Step 1: 添加 Outbase 设置 key**

在 `SettingsService` 类中添加：

```dart
static const keyOutbaseSessionId = 'OUTBASE_SESSION_ID';
static const keyUploadToOutbase = 'UPLOAD_TO_OUTBASE';
```

在 `allKeys` 列表中添加这两个 key。

- [ ] **Step 2: 验证**

Run: `dart analyze lib/services/settings_service.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add lib/services/settings_service.dart
git commit -m "feat(settings): add Outbase session and upload toggle keys"
```

---

### Task 3: API 客户端 — OutbaseClient

**Files:**
- Create: `lib/services/outbase_client.dart`
- Create: `test/services/outbase_client_test.dart`

- [ ] **Step 1: 编写 OutbaseClient 单元测试**

创建 `test/services/outbase_client_test.dart`，测试：
- CDN 上传成功 + API 注册成功 → `success: true`
- CDN 上传成功 + API 返回 "相同时间内已存在其他运动数据" → `alreadyUploaded: true`
- CDN 上传 4xx → `OutbasePermanentError`
- CDN 上传网络错误 → `OutbaseRetriableError`
- CDN 上传成功 + API 注册 4xx → `OutbasePermanentError`（两步流程中第二步失败）
- CDN 上传成功 + API 注册网络错误 → `OutbaseRetriableError`
- API 返回 401/session 过期 → `OutbasePermanentError`（提示重新登录）

使用 `dio` 的 `HttpClientAdapter` mock HTTP 请求。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/outbase_client_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现 OutbaseClient**

创建 `lib/services/outbase_client.dart`：
- `OutbaseUploadResult` 类（success, alreadyUploaded, message）
- `OutbasePermanentError` 异常类（4xx 错误，包括 401 session 过期）
- `OutbaseRetriableError` 异常类（网络错误或 5xx）
- `OutbaseClient` 类：
  - 构造函数：`sessionId`, 可选 `Dio`
  - `uploadFit(File file)` 方法：
    1. 读取文件字节
    2. 生成 GUID（UUID v4 格式，32 hex + 4 hyphens）
    3. 构建 CDN URL：
       - base: `https://melon-gateway.immomo.com/zeusfit/resource/upload`
       - `source=zeusfit`
       - `id={guid}{yyyyMMdd}`（如 `2bd492d6-fec2-4c55-b9e6-becd7451db66220260712`）
       - `uri=/resource/{guid[0:2]}/{guid[2:4]}/{guid}.fit`
       - `momoid=0`
    4. POST CDN 上传（FormData with file, Cookie: sessionId={sessionId}）
    5. 验证 CDN 响应 `message == "SUCCESS"`
    6. 计算 sign = MD5 hex of file bytes（32 char lowercase hex）
    7. POST API 注册：
       - URL: `https://melon-gateway.immomo.com/zeusfit/api/h5/sport/upload/fit`
       - Body: `{fitGuid, sign, fileName, fileSize}`
       - Headers: `Cookie: sessionId={sessionId}`, `Content-Type: application/json`
    8. 处理响应：ec==0 → success, "相同时间内已存在其他运动数据" → alreadyUploaded, 401 → PermanentError(提示重新登录), 其他 → failure

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/outbase_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/outbase_client.dart test/services/outbase_client_test.dart
git commit -m "feat: add OutbaseClient for CDN upload and API registration"
```

---

### Task 4: 平台上传器 — OutbaseFitUploader

**Files:**
- Create: `lib/services/outbase_fit_uploader.dart`
- Create: `test/services/outbase_fit_uploader_test.dart`

- [ ] **Step 1: 编写 OutbaseFitUploader 单元测试**

创建 `test/services/outbase_fit_uploader_test.dart`，测试：
- sessionId 为空 → failure + 提示消息
- 上传成功 → success
- 已上传 → alreadyUploaded
- OutbasePermanentError → failure
- OutbaseRetriableError → failure

Mock `OutbaseClient`。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/outbase_fit_uploader_test.dart`
Expected: FAIL

- [ ] **Step 3: 实现 OutbaseFitUploader**

创建 `lib/services/outbase_fit_uploader.dart`：
- 实现 `FitPlatformUploader` 接口
- `upload()` 方法：
  1. 从 settings 获取 `OUTBASE_SESSION_ID`
  2. 为空则返回 failure（platform: outbase, message: "Outbase 未登录，请先在设置中登录"）
  3. 创建 `OutbaseClient`，调用 `uploadFit()`
  4. 处理结果映射为 `FitUploadPlatformResult`

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/outbase_fit_uploader_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/outbase_fit_uploader.dart test/services/outbase_fit_uploader_test.dart
git commit -m "feat: add OutbaseFitUploader implementing FitPlatformUploader"
```

---

### Task 5: 协调器 — FitUploadCoordinator

**Files:**
- Modify: `lib/services/fit_upload_coordinator.dart`
- Create: `test/services/fit_upload_coordinator_outbase_test.dart`

- [ ] **Step 1: 编写 FitUploadCoordinator Outbase 单元测试**

创建 `test/services/fit_upload_coordinator_outbase_test.dart`，测试：
- `resolveUploadPlan()` 当 `UPLOAD_TO_OUTBASE=true` 时包含 `outbase`
- `resolveUploadPlan()` 当 `UPLOAD_TO_OUTBASE=false` 时不包含 `outbase`
- `_hasRequiredConfiguration()` 当 `OUTBASE_SESSION_ID` 为空时返回 `hasMissingConfiguration: true`
- `_hasRequiredConfiguration()` 当 `OUTBASE_SESSION_ID` 非空时返回 `hasMissingConfiguration: false`
- `_targetLabel()` 包含 Outbase 时的标签生成（单独、两平台、三平台、四平台组合）
- `uploadFile()` 上传到 Outbase 时调用正确的 uploader

Mock `FitPlatformUploader`。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/fit_upload_coordinator_outbase_test.dart`
Expected: FAIL

- [ ] **Step 3: 添加 outbase 枚举值和更新协调器**

1. `FitUploadPlatform` 枚举添加 `outbase`
2. `FitUploadCoordinator` 构造函数添加 `FitPlatformUploader? outbaseUploader` 参数
3. 添加 `_outbaseUploader` 字段（默认 `OutbaseFitUploader()`）
4. `resolveUploadPlan()` 中检查 `UPLOAD_TO_OUTBASE`
5. `_uploadToPlatform()` 的 switch 添加 `FitUploadPlatform.outbase => _outbaseUploader`
6. `_hasRequiredConfiguration()` 添加 Outbase 检查（`OUTBASE_SESSION_ID` 非空）
7. `_targetLabel()` 重构为程序化方式：
   ```dart
   String _targetLabel(List<FitUploadPlatform> targets) {
     final labels = targets.map(_singlePlatformLabel).toList();
     if (labels.length == 1) return labels.first;
     if (labels.length == 2) return '${labels.first} 和${labels.last}';
     return labels.join('、');
   }
   String _singlePlatformLabel(FitUploadPlatform p) {
     return switch (p) {
       FitUploadPlatform.strava => 'Strava',
       FitUploadPlatform.xingzhe => '行者',
       FitUploadPlatform.intervalsIcu => 'Intervals.icu',
       FitUploadPlatform.outbase => 'Outbase',
     };
   }
   ```
8. 添加 `import 'outbase_fit_uploader.dart';`

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/services/fit_upload_coordinator_outbase_test.dart`
Expected: PASS

- [ ] **Step 5: 运行分析**

Run: `dart analyze lib/services/fit_upload_coordinator.dart`
Expected: 无错误

- [ ] **Step 6: Commit**

```bash
git add lib/services/fit_upload_coordinator.dart test/services/fit_upload_coordinator_outbase_test.dart
git commit -m "feat(coordinator): add Outbase platform support with tests"
```

---

### Task 6: 同步引擎 — SyncEngine

**Files:**
- Modify: `lib/services/sync_engine.dart`
- Create: `test/services/sync_engine_outbase_test.dart`

**注意**: SyncEngine 直接使用 `OutbaseClient`（与 Strava/Xingzhe/Intervals.icu 模式一致），不通过 FitUploadCoordinator。FitUploadCoordinator 用于 SharedFitUploadService（分享上传场景）。

- [ ] **Step 1: 编写 SyncEngine Outbase 单元测试**

创建 `test/services/sync_engine_outbase_test.dart`，测试：
- `uploadToOutbase=true` 且 `outbaseClient` 非空时，上传 Outbase
- `uploadToOutbase=false` 时，不上传 Outbase
- Outbase 上传成功 → `SyncSummary.outbaseSuccess++`
- Outbase 上传已存在 → `SyncSummary.outbaseDeduped++`
- Outbase 上传失败 → `SyncSummary.outbaseFailed++`
- Outbase dedup 检查：已上传过的活动跳过 Outbase
- 所有平台（含 Outbase）都 dedup 时，计入 deduped
- `SyncProgress.outbaseEnabled` 和 `outbaseUploaded` 正确更新
- `SyncRecord.uploadedToOutbase` 正确设置

Mock `OutbaseClient` 和 `OneLapClient`。

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/services/sync_engine_outbase_test.dart`
Expected: FAIL

- [ ] **Step 3: 添加 Outbase 字段和构造参数**

1. 添加 `import 'outbase_client.dart';`
2. 添加 `OutbaseClient? outbaseClient` 字段
3. 添加 `bool uploadToOutbase` 字段
4. 构造函数添加对应参数

- [ ] **Step 4: 添加 _uploadToOutbase() 方法**

遵循 `_uploadToStrava` 模式，实现 `_uploadToOutbase()` 方法：
- 检查 dedup 状态（`stateStore.isAlreadyUploaded(fingerprint, 'outbase')`）
- 如果已 dedup，返回 deduped 结果
- 调用 `outbaseClient.uploadFit(uploadFile)`
- 处理结果：
  - `success` → `markPlatformSynced(fingerprint, 'outbase', null)`, 返回 success
  - `alreadyUploaded` → `markPlatformSynced(fingerprint, 'outbase', null)`, 返回 deduped
  - `OutbasePermanentError` → 返回 failed
  - `OutbaseRetriableError` → 返回 failed
- 返回 `_PlatformUploadResult`

- [ ] **Step 5: 集成到 runOnce()**

1. `progress` 初始化添加 `outbaseEnabled: uploadToOutbase`
2. 添加 `outbaseSuccess`, `outbaseFailed`, `outbaseDeduped`, `outbaseFailures` 计数变量
3. Phase 2 dedup 检查添加 `skipOutbase` 逻辑（在 `skipIntervalsIcu` 之后）
4. "所有平台都 dedup" 检查添加 `(!uploadToOutbase || skipOutbase)`
5. `uploadFutures` 添加 Outbase 上传任务
6. 结果聚合添加 Outbase 统计（与 stravaResults/xingzheResults/intervalsIcuResults 同模式）
7. `progress.copyWith()` 添加 `outbaseUploaded`
8. `_failedRecord()` 添加 Outbase 平台结果
9. `SyncSummary` 构造添加 Outbase 字段
10. `SyncRecord` 构造添加 `uploadedToOutbase: uploadToOutbase`

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/services/sync_engine_outbase_test.dart`
Expected: PASS

- [ ] **Step 7: 运行分析**

Run: `dart analyze lib/services/sync_engine.dart`
Expected: 无错误

- [ ] **Step 8: Commit**

```bash
git add lib/services/sync_engine.dart test/services/sync_engine_outbase_test.dart
git commit -m "feat(sync): integrate Outbase upload into SyncEngine with tests"
```

---

### Task 7: 共享上传服务 — SharedFitUploadService

**Files:**
- Modify: `lib/services/shared_fit_upload_service.dart`

- [ ] **Step 1: 添加 Outbase 平台映射**

1. `_mapSyncPlatform()` 添加 `FitUploadPlatform.outbase => SyncPlatform.outbase`
2. `_platformLabel()` 添加 `FitUploadPlatform.outbase => 'Outbase'`
3. `_persistSyncHistoryIfNeeded()` 中 `SyncRecord` 构造添加 `uploadedToOutbase`

- [ ] **Step 2: 运行分析**

Run: `dart analyze lib/services/shared_fit_upload_service.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add lib/services/shared_fit_upload_service.dart
git commit -m "feat(shared-upload): add Outbase platform mapping"
```

---

### Task 8: WebView 登录 — OutbaseSettingsScreen

**Files:**
- Create: `lib/screens/outbase_settings_screen.dart`

- [ ] **Step 1: 实现 OutbaseSettingsScreen**

创建 `lib/screens/outbase_settings_screen.dart`：
- `StatefulWidget`，使用 `webview_flutter`
- 初始 URL: `https://outbase.cn/zeusfit/official-website/dashboard.html?tab=import`
- 如果被重定向到 login.html，继续等待用户登录
- `NavigationDelegate` 监听 URL 变化：
  - 当 URL 包含 `dashboard.html` 时，注入 JS 读取 `document.cookie`
  - 从 cookie 中提取 `sessionId`（正则匹配 `sessionId=([^;]+)`）
  - 保存到 `flutter_secure_storage`（key: `OUTBASE_SESSION_ID`）
  - 同时在 settings 中保存 `UPLOAD_TO_OUTBASE=true`
- UI：
  - 未登录：全屏 WebView
  - 已登录：显示状态（绿色勾 + "已登录"）+ 重新登录按钮 + 退出登录按钮
- 退出登录：清除 `OUTBASE_SESSION_ID`，设置 `UPLOAD_TO_OUTBASE=false`

- [ ] **Step 2: 运行分析**

Run: `dart analyze lib/screens/outbase_settings_screen.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add lib/screens/outbase_settings_screen.dart
git commit -m "feat(ui): add OutbaseSettingsScreen with WebView login"
```

---

### Task 9: 设置页面 — SettingsScreen

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: 添加 Outbase 平台卡片**

1. 添加 `import 'outbase_settings_screen.dart';`
2. 添加状态变量：`_uploadToOutbase`, `_savingUploadToOutbase`, `_pendingUploadToOutbase`, `_confirmedUploadToOutbase`
3. `_load()` 中加载 `UPLOAD_TO_OUTBASE` 设置（默认 false）
4. 实现 `_toggleUploadToOutbase()` 方法（参照 `_toggleUploadToIntervalsIcu` 模式）
5. `_otherPlatformsEnabled()` 添加 `bool outbase` 参数
6. 所有 `_otherPlatformsEnabled()` 调用处添加 `outbase: _uploadToOutbase`
7. 在 `_buildPlatformCard()` 调用列表中添加 Outbase 卡片（在 Intervals.icu 之后）

- [ ] **Step 2: 运行分析**

Run: `dart analyze lib/screens/settings_screen.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart
git commit -m "feat(ui): add Outbase platform card to settings screen"
```

---

### Task 10: HomeScreen — 同步逻辑和进度显示

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 添加 Outbase 同步逻辑**

1. 添加 `import '../services/outbase_client.dart';`
2. 在 `_startSync()` 中：
   - 加载 `uploadToOutbase` 和 `outbaseSessionId` 设置
   - 添加 Outbase 凭证检查（sessionId 为空时提示）
   - "至少选择一个平台" 检查添加 `!uploadToOutbase`
   - 创建 `OutbaseClient`（如果启用）
   - 传递给 `SyncEngine(outbaseClient: outbase, uploadToOutbase: uploadToOutbase)`
   - `SyncProgress` 构造添加 `outbaseEnabled: uploadToOutbase`

- [ ] **Step 2: 添加 Outbase 进度显示**

在 `_SyncProgressDialog` 中添加 Outbase 进度条（参照 Intervals.icu 模式）：
```dart
if (progress.outbaseEnabled && progress.uploadTotal > 0) ...[
  const Text('上传至 Outbase', style: TextStyle(fontSize: 13)),
  const SizedBox(height: 4),
  LinearProgressIndicator(
    value: progress.uploadTotal > 0
        ? progress.outbaseUploaded / progress.uploadTotal
        : 0,
  ),
  const SizedBox(height: 2),
  Text(
    '${progress.outbaseUploaded}/${progress.uploadTotal}',
    style: const TextStyle(fontSize: 12, color: Colors.grey),
  ),
],
```

- [ ] **Step 3: 添加 Outbase banner 显示**

在 `_showSyncResult()` 和 banner 相关逻辑中添加 Outbase 统计（参照 Intervals.icu 模式）。

- [ ] **Step 4: 运行分析**

Run: `dart analyze lib/screens/home_screen.dart`
Expected: 无错误

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat(home): add Outbase sync logic, progress, and banner display"
```

---

### Task 11: 配置导入导出 — ConfigService

**Files:**
- Modify: `lib/services/config_service.dart`

- [ ] **Step 1: 添加 Outbase 配置支持**

1. `exportConfig()` 中添加 Outbase 部分：
   ```json
   {
     "outbase": {
       "sessionId": "...",
       "uploadToOutbase": true
     }
   }
   ```
2. `importConfig()` 中读取 Outbase 配置
3. 导入旧配置（无 `outbase` key）时默认禁用

- [ ] **Step 2: 运行分析**

Run: `dart analyze lib/services/config_service.dart`
Expected: 无错误

- [ ] **Step 3: Commit**

```bash
git add lib/services/config_service.dart
git commit -m "feat(config): add Outbase section to config export/import"
```

---

### Task 12: 验证和收尾

- [ ] **Step 1: 运行完整验证**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: 全部通过

- [ ] **Step 2: 修复任何格式或分析问题**

如有问题，修复后重新运行验证。

- [ ] **Step 3: 最终 Commit**

```bash
git add -A
git commit -m "chore: fix format/analyze issues for Outbase integration"
```

---

## 执行顺序

Tasks 必须按顺序执行，因为存在依赖关系：

1. **Task 1** (模型层) → 无依赖
2. **Task 2** (设置层) → 无依赖，可与 Task 1 并行
3. **Task 3** (API 客户端) → 依赖 Task 1
4. **Task 4** (上传器) → 依赖 Task 3
5. **Task 5** (协调器) → 依赖 Task 4
6. **Task 6** (同步引擎) → 依赖 Task 5
7. **Task 7** (共享上传) → 依赖 Task 5
8. **Task 8** (WebView 登录) → 依赖 Task 2
9. **Task 9** (设置页面) → 依赖 Task 8
10. **Task 10** (HomeScreen) → 依赖 Task 6
11. **Task 11** (配置导入导出) → 依赖 Task 2
12. **Task 12** (验证) → 依赖所有前序任务
