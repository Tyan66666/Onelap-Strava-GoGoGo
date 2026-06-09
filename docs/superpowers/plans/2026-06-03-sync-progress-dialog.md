# 同步进度对话框 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在同步过程中弹出对话框，实时展示下载和上传进度，同步完成后关闭进度对话框并弹出结果对话框。

**Architecture:** 新增 `SyncProgress` 数据模型，`SyncEngine.runOnce()` 通过 `onProgress` 回调推送进度，`HomeScreen` 使用 `ValueNotifier` + `ValueListenableBuilder` 驱动对话框 UI 刷新。

**Tech Stack:** Flutter / Dart, ValueNotifier, ValueListenableBuilder

---

## File Structure

| 文件 | 职责 |
|------|------|
| `lib/models/sync_progress.dart` | **新增** — 进度数据模型，含 `copyWith` |
| `lib/services/sync_engine.dart` | **修改** — 添加 `onProgress` 回调参数，在关键位置推送进度 |
| `lib/screens/home_screen.dart` | **修改** — 新增 `_SyncProgressDialog` widget，改造 `_sync()` 方法，提取 `_SyncResultContent` |
| `test/models/sync_progress_test.dart` | **新增** — `SyncProgress.copyWith` 测试 |

---

### Task 1: 新增 SyncProgress 数据模型

**Files:**
- Create: `lib/models/sync_progress.dart`
- Test: `test/models/sync_progress_test.dart`

- [ ] **Step 1: 编写 SyncProgress 模型测试**

```dart
// test/models/sync_progress_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/sync_progress.dart';

void main() {
  group('SyncProgress', () {
    test('default constructor has zero values', () {
      const p = SyncProgress();
      expect(p.totalActivities, 0);
      expect(p.downloaded, 0);
      expect(p.uploadTotal, 0);
      expect(p.stravaUploaded, 0);
      expect(p.xingzheUploaded, 0);
      expect(p.stravaEnabled, false);
      expect(p.xingzheEnabled, false);
    });

    test('copyWith returns new instance with updated fields', () {
      const p = SyncProgress();
      final p2 = p.copyWith(
        totalActivities: 10,
        downloaded: 5,
        stravaEnabled: true,
      );
      expect(p2.totalActivities, 10);
      expect(p2.downloaded, 5);
      expect(p2.stravaEnabled, true);
      expect(p2.uploadTotal, 0); // unchanged
    });

    test('copyWith with no arguments returns identical values', () {
      const p = SyncProgress(
        totalActivities: 3,
        downloaded: 2,
        uploadTotal: 1,
        stravaUploaded: 1,
        xingzheUploaded: 0,
        stravaEnabled: true,
        xingzheEnabled: true,
      );
      final p2 = p.copyWith();
      expect(p2.totalActivities, 3);
      expect(p2.downloaded, 2);
      expect(p2.uploadTotal, 1);
      expect(p2.stravaUploaded, 1);
      expect(p2.xingzheUploaded, 0);
      expect(p2.stravaEnabled, true);
      expect(p2.xingzheEnabled, true);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
flutter test test/models/sync_progress_test.dart
```

- [ ] **Step 3: 创建 SyncProgress 模型**

```dart
// lib/models/sync_progress.dart
class SyncProgress {
  final int totalActivities;
  final int downloaded;
  final int uploadTotal;
  final int stravaUploaded;
  final int xingzheUploaded;
  final bool stravaEnabled;
  final bool xingzheEnabled;

  const SyncProgress({
    this.totalActivities = 0,
    this.downloaded = 0,
    this.uploadTotal = 0,
    this.stravaUploaded = 0,
    this.xingzheUploaded = 0,
    this.stravaEnabled = false,
    this.xingzheEnabled = false,
  });

  SyncProgress copyWith({
    int? totalActivities,
    int? downloaded,
    int? uploadTotal,
    int? stravaUploaded,
    int? xingzheUploaded,
    bool? stravaEnabled,
    bool? xingzheEnabled,
  }) {
    return SyncProgress(
      totalActivities: totalActivities ?? this.totalActivities,
      downloaded: downloaded ?? this.downloaded,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      stravaUploaded: stravaUploaded ?? this.stravaUploaded,
      xingzheUploaded: xingzheUploaded ?? this.xingzheUploaded,
      stravaEnabled: stravaEnabled ?? this.stravaEnabled,
      xingzheEnabled: xingzheEnabled ?? this.xingzheEnabled,
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
flutter test test/models/sync_progress_test.dart
```

- [ ] **Step 5: 运行格式化和全量测试**

```bash
dart format --output=none --set-exit-if-changed lib/models/sync_progress.dart test/models/sync_progress_test.dart
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/models/sync_progress.dart test/models/sync_progress_test.dart
git commit -m "feat: add SyncProgress data model with copyWith"
```

---

### Task 2: SyncEngine 添加 onProgress 回调

**Files:**
- Modify: `lib/services/sync_engine.dart`

**当前 `runOnce()` 签名（`sync_engine.dart:72`）：**
```dart
Future<SyncSummary> runOnce({
  DateTime? sinceDate,
  int lookbackDays = 3,
}) async {
```

**修改后签名：**
```dart
Future<SyncSummary> runOnce({
  DateTime? sinceDate,
  int lookbackDays = 3,
  void Function(SyncProgress)? onProgress,
}) async {
```

- [ ] **Step 1: 在 `runOnce()` 开头添加 import 和局部变量**

在 `sync_engine.dart` 顶部添加 import：
```dart
import '../models/sync_progress.dart';
```

在 `runOnce()` 方法内，`activities` 获取之前，添加：
```dart
var progress = SyncProgress(
  stravaEnabled: uploadToStrava,
  xingzheEnabled: uploadToXingzhe,
);
```

- [ ] **Step 2: 获取活动列表后推送进度**

在 `activities = await oneLapClient.listFitActivities(since: since);` 之后、`int deduped = 0` 之前，添加：
```dart
progress = progress.copyWith(totalActivities: activities.length);
onProgress?.call(progress);
```

- [ ] **Step 3: 下载完成后推送进度**

在 `final downloadResults = await pool.runAll(downloadTasks);` 之后，添加对 `downloadResults` 的遍历推送。但当前代码是把下载和处理放在一个循环里（`for (final dlResult in downloadResults)`），所以需要在每个 `dlResult` 处理完后推送下载进度。

在 `for (final dlResult in downloadResults)` 循环体的最开头（`if (dlResult is! _DownloadResult) continue;` 之后），添加下载计数推送。需要一个局部计数器：

在 `for` 循环前添加：
```dart
int processedCount = 0;
```

在循环体末尾（`continue` 之前的所有分支末尾）添加：
```dart
processedCount++;
progress = progress.copyWith(downloaded: processedCount);
onProgress?.call(progress);
```

注意：需要在每个 `continue` 语句之前都添加这三行（下载失败时、去重跳过时、正常处理完时）。

- [ ] **Step 4: 上传完成后推送进度**

上传计数逻辑说明：
- `uploadTotal`：每个活动进入上传阶段时 +1（去重跳过的不计入）
- `stravaUploaded` / `xingzheUploaded`：每个平台上传成功时 +1（`_PlatformUploadResult.success` 为 0 或 1）
- 一个活动可能 Strava 成功但行者失败，两个计数器独立递增

在 `// ---- 5. 坐标转换 ----` 之前（即去重检查通过、需要上传的活动），添加：
```dart
progress = progress.copyWith(uploadTotal: progress.uploadTotal + 1);
onProgress?.call(progress);
```

在 `// ---- 6. 更新计数 ----` 之后（即 `_uploadToStrava` / `_uploadToXingzhe` 结果聚合完成后），添加：
```dart
final stravaInc = stravaResults.fold<int>(0, (sum, r) => sum + r.success);
final xingzheInc = xingzheResults.fold<int>(0, (sum, r) => sum + r.success);
progress = progress.copyWith(
  stravaUploaded: progress.stravaUploaded + stravaInc,
  xingzheUploaded: progress.xingzheUploaded + xingzheInc,
);
onProgress?.call(progress);
```

- [ ] **Step 5: 运行格式化和测试**

```bash
dart format --output=none --set-exit-if-changed lib/services/sync_engine.dart
flutter test test/services/sync_engine_test.dart
```

- [ ] **Step 6: Commit**

```bash
git add lib/services/sync_engine.dart
git commit -m "feat: add onProgress callback to SyncEngine.runOnce"
```

---

### Task 3: HomeScreen 改造 — 进度对话框

**Files:**
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: 添加 import**

在 `home_screen.dart` 顶部添加：
```dart
import '../models/sync_progress.dart';
```

- [ ] **Step 2: 创建 `_SyncProgressDialog` widget**

在 `_HomeScreenState` 类之前（或文件末尾），添加：

```dart
class _SyncProgressDialog extends StatelessWidget {
  final SyncProgress progress;

  const _SyncProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在同步'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 下载进度
          if (progress.totalActivities > 0) ...[
            const Text('下载活动', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress.totalActivities > 0
                  ? progress.downloaded / progress.totalActivities
                  : 0,
            ),
            const SizedBox(height: 2),
            Text(
              '${progress.downloaded}/${progress.totalActivities}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
          ],
          // Strava 上传进度
          if (progress.stravaEnabled && progress.uploadTotal > 0) ...[
            const Text('上传至 Strava', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress.uploadTotal > 0
                  ? progress.stravaUploaded / progress.uploadTotal
                  : 0,
            ),
            const SizedBox(height: 2),
            Text(
              '${progress.stravaUploaded}/${progress.uploadTotal}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
          ],
          // 行者上传进度
          if (progress.xingzheEnabled && progress.uploadTotal > 0) ...[
            const Text('上传至行者', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress.uploadTotal > 0
                  ? progress.xingzheUploaded / progress.uploadTotal
                  : 0,
            ),
            const SizedBox(height: 2),
            Text(
              '${progress.xingzheUploaded}/${progress.uploadTotal}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          // 等待状态
          if (progress.totalActivities == 0)
            const Text('正在获取活动列表...', style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: 改造 `_sync()` 方法**

将 `_sync()` 方法中从 `setState(() { _syncing = true; ...` 到方法末尾的逻辑改造为：

```dart
Future<void> _sync() async {
  setState(() {
    _syncing = true;
    _error = null;
  });

  try {
    保留以下变量的赋值逻辑（来自 settings 加载）：
- `username`, `password` — OneLap 凭证
- `stravaClientId`, `stravaClientSecret`, `stravaRefreshToken`, `stravaAccessToken`, `stravaExpiresAt` — Strava 凭证
- `xingzheUsername`, `xingzhePassword` — 行者凭证
- `gcjCorrectionEnabled`, `uploadToStrava`, `uploadToXingzhe` — 开关

保留凭证校验逻辑（`if (username.isEmpty ...` 等 early return）。

保留 `OneLapClient`、`StravaClient`、`XingzheClient` 的构造和 `SyncEngine` 的构造。

关键改动点：`engine.runOnce()` 调用替换为带 `onProgress` 的版本，并包裹在进度对话框中。

    // 构造 engine 之后
    final engine = SyncEngine(
      oneLapClient: oneLap,
      stravaClient: strava,
      xingzheClient: xingzhe,
      stateStore: _stateStore,
      gcjCorrectionEnabled: gcjCorrectionEnabled,
      uploadToStrava: uploadToStrava,
      uploadToXingzhe: uploadToXingzhe,
      rewriteService: FitCoordinateRewriteService(),
    );

    final progressNotifier = ValueNotifier<SyncProgress>(
      SyncProgress(
        stravaEnabled: uploadToStrava,
        xingzheEnabled: uploadToXingzhe,
      ),
    );

    if (!mounted) return;
    late BuildContext dialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return ValueListenableBuilder<SyncProgress>(
          valueListenable: progressNotifier,
          builder: (ctx, progress, _) =>
              _SyncProgressDialog(progress: progress),
        );
      },
    );

    try {
      final summary = await engine.runOnce(
        lookbackDays:
            int.tryParse(settings[SettingsService.keyLookbackDays] ?? '') ?? 3,
        onProgress: (p) => progressNotifier.value = p,
      );

      await _loadLastSyncTime();

      final banner = SyncResultBanner.fromSyncSummary(summary);
      await _stateStore.saveSyncResultBanner(banner);
      await _loadBanners();

      if (!mounted) return;
      Navigator.of(dialogContext).pop();
      setState(() => _syncing = false);
      _showSyncResult(summary);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(dialogContext).pop();
      setState(() {
        _error = e.toString();
        _syncing = false;
      });
    } finally {
      progressNotifier.dispose();
    }
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = e.toString();
      _syncing = false;
    });
  }
}
```

- [ ] **Step 4: 运行格式化和测试**

```bash
dart format --output=none --set-exit-if-changed lib/screens/home_screen.dart
flutter analyze
flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: show sync progress dialog with download/upload progress bars"
```

---

### Task 4: 提取 _SyncResultContent（可选重构）

**Files:**
- Modify: `lib/screens/home_screen.dart`

此步骤为可选重构，将 `_showSyncResult()` 中的 `content` 部分提取为独立 widget。

- [ ] **Step 1: 提取 widget**

将 `_showSyncResult()` 中 `content: SingleChildScrollView(child: Column(...))` 的内容提取为 `_SyncResultContent` StatelessWidget。

- [ ] **Step 2: 在 `_showSyncResult()` 中使用新 widget**

- [ ] **Step 3: 运行测试确认无回归**

```bash
flutter analyze
flutter test
```

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "refactor: extract _SyncResultContent from _showSyncResult"
```

---

### Task 5: 端到端验证

- [ ] **Step 1: 运行完整验证流水线**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

- [ ] **Step 2: 构建 APK 验证编译通过**

```bash
flutter build apk --debug
```
