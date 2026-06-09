# 同步进度对话框设计

## 目标

在同步过程中弹出对话框，实时展示下载和上传进度，同步完成后关闭进度对话框并弹出结果对话框。

## UI 设计

### 同步中状态

```
┌──────────────────────────────────┐
│         正在同步                  │
│                                  │
│  下载活动      ████████████░░ 8/10│
│                                  │
│  上传至 Strava  ██████░░░░░░ 5/8 │
│  上传至行者     ████░░░░░░░░ 3/8 │
│                                  │
│  [同步中...]                     │
└──────────────────────────────────┘
```

- 未启用的平台不显示对应进度条
- 去重跳过的活动不计入上传总数
- 不可关闭（barrierDismissible: false）

### 同步完成状态

同步完成后，关闭进度对话框，弹出结果对话框（两个对话框，非同一个）。
结果对话框复用 `_showSyncResult()` 现有逻辑，其中内容提取为 `_SyncResultContent` widget 以便维护。

### 错误场景

| 场景 | 对话框行为 |
|------|-----------|
| `runOnce()` 正常完成 | 关闭进度对话框，弹出结果对话框 |
| `runOnce()` 抛异常 | 关闭进度对话框，`_sync()` 中 catch 处理，设置 `_error` 文本 |
| OneLap 风控拦截 | `runOnce()` 正常返回 `SyncSummary(abortedReason: 'risk-control')`，关闭进度对话框，弹出"同步中止"对话框 |

## 数据模型

新增 `lib/models/sync_progress.dart`：

```dart
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
  });
}
```

## SyncEngine 改动

`runOnce()` 新增可选参数：

```dart
Future<SyncSummary> runOnce({
  DateTime? sinceDate,
  int lookbackDays = 3,
  void Function(SyncProgress)? onProgress,  // 新增
}) async { ... }
```

### 推送时机

| 时机 | 推送内容 |
|------|---------|
| 获取活动列表后 | `totalActivities = N` |
| 每个文件下载完成 | `downloaded++` |
| 去重跳过时 | 不计入 `uploadTotal` |
| 需上传的活动确定后 | `uploadTotal` = 去重后实际需上传的活动数 |
| 每个平台上传完成 | `stravaUploaded++` 或 `xingzheUploaded++` |

### 内部实现

在 `runOnce()` 内部维护一个 `SyncProgress` 实例，每次状态变化时调用 `onProgress?.call(progress)`。

关键修改点：
1. `activities` 获取后立即推送
2. `downloadResults` 遍历中每完成一个文件推送
3. 去重跳过的活动不计入 `uploadTotal`
4. `_uploadToStrava` / `_uploadToXingzhe` 完成后推送
5. Strava 和 Xingzhe 并行上传，各自独立计数

## HomeScreen 改动

### 新增 `_showSyncDialog` 方法

替代现有的同步流程中的 `_syncing` 状态管理，改为对话框驱动。

**UI 刷新方案**：使用 `ValueNotifier<SyncProgress>` + `ValueListenableBuilder`。
- `_sync()` 中创建 `ValueNotifier<SyncProgress>`
- 对话框内用 `ValueListenableBuilder` 监听变化并刷新进度条
- `onProgress` 回调中通过 `notifier.value = p` 触发刷新

**onComplete 触发时机**：`runOnce()` 返回后，由 `_sync()` 方法主动调用对话框的完成方法。对话框本身不监听终止条件。

```dart
Future<void> _sync() async {
  // ... 现有的设置加载和校验逻辑不变 ...

  final progressNotifier = ValueNotifier<SyncProgress>(
    SyncProgress(stravaEnabled: uploadToStrava, xingzheEnabled: uploadToXingzhe),
  );

  // 弹出进度对话框，获取 StateSetter 闭包
  if (!mounted) return;
  late BuildContext dialogContext;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      dialogContext = ctx;
      return ValueListenableBuilder<SyncProgress>(
        valueListenable: progressNotifier,
        builder: (ctx, progress, _) => _SyncProgressDialog(progress: progress),
      );
    },
  );

  try {
    final summary = await engine.runOnce(
      lookbackDays: ...,
      onProgress: (p) => progressNotifier.value = p,
    );

    // 保存 banner
    final banner = SyncResultBanner.fromSyncSummary(summary);
    await _stateStore.saveSyncResultBanner(banner);
    await _loadBanners();

    // 关闭进度对话框，弹出结果对话框
    if (!mounted) return;
    Navigator.of(dialogContext).pop();
    _showSyncResult(summary);
  } catch (e) {
    // 关闭进度对话框，显示错误
    if (!mounted) return;
    Navigator.of(dialogContext).pop();
    setState(() => _error = e.toString());
  } finally {
    progressNotifier.dispose();
  }
}
```

### `_SyncProgressDialog` 组件

独立的 StatelessWidget，仅负责展示当前 `SyncProgress` 进度条。不管理生命周期，不做状态切换——由外部 `_sync()` 方法控制对话框的打开和关闭。

### `_SyncResultContent` 提取

从现有 `_showSyncResult()` 中提取对话框内容为公共 widget `_SyncResultContent`，供结果对话框使用。提取的目的是减少 `_showSyncResult()` 方法体积，便于维护。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `lib/models/sync_progress.dart` | **新增** — 进度数据模型 |
| `lib/services/sync_engine.dart` | 添加 `onProgress` 回调，在关键位置推送进度 |
| `lib/screens/home_screen.dart` | 新增 `_SyncProgressDialog`、`_SyncResultContent`，改造 `_sync()` 方法 |
| `test/models/sync_progress_test.dart` | **新增** — 进度模型的 copyWith 测试 |

## 不改动的部分

- `SyncSummary` 模型不变
- `SyncResultBanner` 模型不变
- `StateStore` 不变
- 设置页面不变
- 同步历史页面不变
