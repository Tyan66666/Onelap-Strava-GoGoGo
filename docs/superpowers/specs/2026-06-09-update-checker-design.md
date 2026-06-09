# 版本检查功能设计

## 目标

每次启动 App 时自动检查是否有新版本，有新版本时弹窗提示用户并提供下载链接。

## 行为规格

| 场景 | 行为 |
|------|------|
| 启动时有新版本 | 弹出对话框，显示版本号 + 更新日志，提供"下载更新"按钮 |
| 启动时无新版本 | 静默跳过，无任何 UI 提示 |
| 网络错误 / API 失败 | 静默跳过，不影响 App 正常使用 |
| GitHub API 限流 (403) | 静默跳过 |
| 版本比较失败 | 静默跳过 |

## UI 设计

### 更新提示对话框

```
┌──────────────────────────────────┐
│         发现新版本                │
│                                  │
│  最新版本: v1.0.21               │
│  当前版本: v1.0.20               │
│                                  │
│  更新内容:                       │
│  ## 更新内容                     │
│  - 修复了 XXX 问题               │
│  - 新增 YYY 功能                 │
│                                  │
│  ┌──────────┐  ┌──────────────┐  │
│  │ 下载更新  │  │  稍后再说    │  │
│  └──────────┘  └──────────────┘  │
└──────────────────────────────────┘
```

- "下载更新"按钮：打开 GitHub Release 页面（`https://github.com/Tyan66666/Onelap-Strava-GoGoGo/releases/tag/vX.Y.Z`）
- "稍后再说"按钮：关闭弹窗
- 弹窗可点击外部关闭（`barrierDismissible: true`）
- 无网络时不会弹出此对话框

### 关于对话框增强

在现有 `_showAbout()` 的版本显示行下方，添加一行蓝色可点击文字"检查更新"，点击后触发 `_checkForUpdate()` 并显示结果。

## 数据模型

新增 `lib/models/update_info.dart`：

```dart
class UpdateInfo {
  final bool hasUpdate;
  final String latestVersion;   // "1.0.21"
  final String currentVersion;  // "1.0.20"
  final String releaseNotes;    // GitHub release body (markdown)
  final String downloadUrl;     // https://github.com/.../releases/tag/v1.0.21

  const UpdateInfo({
    required this.hasUpdate,
    this.latestVersion = '',
    this.currentVersion = '',
    this.releaseNotes = '',
    this.downloadUrl = '',
  });

  /// Shorthand for error/silent-skip cases.
  factory UpdateInfo.noUpdate(String current) => UpdateInfo(
    hasUpdate: false,
    currentVersion: current,
  );
}
```

## 服务层

新增 `lib/services/update_checker.dart`：

### UpdateChecker.check()

```dart
class UpdateChecker {
  static const _owner = 'Tyan66666';
  static const _repo = 'Onelap-Strava-GoGoGo';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static Future<UpdateInfo> check() async { ... }
}
```

**流程：**
1. 通过 `PackageInfo.fromPlatform()` 获取当前版本号（如 `1.0.20`）
2. 使用 `Dio` 请求 GitHub Releases API（30s 超时，与项目风格一致）
3. 解析响应 JSON 中的 `tag_name`（如 `v1.0.21`）和 `body`（release notes）
4. 去掉 `tag_name` 的 `v` 前缀（如 `v1.0.21` → `1.0.21`），按 `.` 分割为 `[major, minor, patch]`（注意：`PackageInfo.fromPlatform()` 返回的版本号本身无 `v` 前缀）
5. 逐段比较：major → minor → patch，任一段较大则 `hasUpdate = true`
6. 任何异常（网络、解析、类型转换）catch 后返回 `UpdateInfo(hasUpdate: false, ...)`

**错误处理原则：** 版本检查是辅助功能，绝不应阻断 App 主流程。所有异常静默处理。

## UI 集成

### 文件：`lib/screens/home_screen.dart`

**修改 `initState`：**

```dart
@override
void initState() {
  super.initState();
  _loadLastSyncTime();
  _loadBanners();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _showAboutIfFirstLaunch();
    _checkForUpdate();  // 新增
  });
}
```

**新增 `_checkForUpdate()` 方法：**

```dart
Future<void> _checkForUpdate() async {
  final info = await UpdateChecker.check();
  if (!mounted || !info.hasUpdate) return;
  // 弹出更新对话框
}
```

**新增 `_showUpdateDialog(UpdateInfo info)` 方法：**

显示更新提示对话框，包含版本号、更新日志、下载按钮。

**修改 `_showAbout()` 方法：**

在版本号显示行下方，添加"检查更新"文字按钮，点击后调用 `_checkForUpdate()`。

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `lib/models/update_info.dart` | 新增 | UpdateInfo 数据模型 |
| `lib/services/update_checker.dart` | 新增 | UpdateChecker 服务（GitHub API 调用 + 版本比较） |
| `lib/screens/home_screen.dart` | 修改 | initState 增加检查调用、新增弹窗方法、关于对话框增加检查入口 |

## 测试计划

- `test/services/update_checker_test.dart`：版本比较逻辑单元测试
  - `1.0.20` vs `1.0.21` → hasUpdate = true
  - `1.0.20` vs `1.0.20` → hasUpdate = false
  - `1.0.20` vs `1.1.0` → hasUpdate = true
  - `2.0.0` vs `1.9.9` → hasUpdate = false
  - 无效版本字符串 → hasUpdate = false
- 网络错误场景：mock Dio 返回错误 → 静默跳过
