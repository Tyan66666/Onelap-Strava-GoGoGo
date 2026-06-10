# 设置页面自动保存设计

## 问题

设置页面有多余的保存按钮，对用户造成困扰：
- "保存上传设置"按钮 — 用户切换上传平台开关后还需要再点一次保存
- 底部"保存"按钮 — 保存所有设置，与其他保存按钮功能重叠

## 改动范围

仅修改 `lib/screens/settings_screen.dart`，不涉及 `SettingsService` 或其他文件。

## 设计

### 1. 上传开关改为自动保存

当前行为：
- `_toggleUploadToStrava(bool)` / `_toggleUploadToXingzhe(bool)` 仅调用 `setState`，不持久化
- 用户必须点击"保存上传设置"按钮才能生效

改为：
- 切换开关时立即调用 `_settingsService.saveSettings()` 保存 `UPLOAD_TO_STRAVA` / `UPLOAD_TO_XINGZHE`
- 守卫逻辑：两个平台不能同时关闭。**先检查再 setState**：在调用 `setState` 之前检查 `if (!value && !otherToggle)` → 显示 SnackBar "至少需要选择一个上传平台"，直接 return，不修改状态。避免 UI 闪烁到无效状态
- 保存失败时回滚 `_uploadToStrava` / `_uploadToXingzhe` 状态到变更前的值，显示错误 SnackBar
- 复用 GCJ 开关的防并发模式（`_pending` 变量队列），避免快速切换导致状态不一致。为每个 toggle 独立维护 `_saving` / `_pending` / `_confirmed` 状态

### 2. 移除两个保存按钮

- 删除"保存上传设置"ElevatedButton（当前 build 方法中上传设置区域的按钮）
- 删除底部"保存"ElevatedButton（build 方法最末尾的按钮）

### 3. 清理无用代码

移除以下代码：
- `_savingUploadSettings` 状态变量
- `_saveUploadSettings()` 方法
- `_save()` 方法（原用于底部保存按钮和 `_authorizeStrava`）

### 4. `_authorizeStrava` 重构

当前 `_authorizeStrava` 在跳转 OAuth 前调用 `_save()` 保存所有设置。改为：
- 仅保存 Strava Client ID 和 Client Secret 两个字段
- 内联保存逻辑，不依赖全局 `_save()` 方法
- **行为变更（有意）**：当前点击"授权 Strava"时如果回溯天数无效会阻止跳转。改后不再检查回溯天数，直接进入 OAuth 流程。这是合理的，因为回溯天数与 OAuth 授权无关，不应阻塞授权流程

### 5. 保留的按钮

| 按钮 | 位置 | 行为 |
|------|------|------|
| "保存 OneLap 账号" | OneLap 区域 | 验证登录 + 保存用户名密码 |
| "保存同步设置" | 同步设置区域 | 保存回溯天数 |
| "登录 行者" | 行者区域 | 验证登录 + 保存用户名密码 |

### 6. 不改动的部分

- Strava 上传模式 SegmentedButton — 已经在 `onSelectionChanged` 中自动保存
- GCJ 开关 — 已经在 `onChanged` 中自动保存
- OneLap / 行者文本输入框 — 保持当前行为，通过各自的按钮保存
- 回溯天数文本输入框 — 保持当前行为，通过"保存同步设置"按钮保存

## 受影响的测试

以下测试需要更新或移除（位于 `test/screens/settings_screen_test.dart`）：

| 测试 | 影响 | 处理 |
|------|------|------|
| `preserves entered credentials after successful Strava auth` (line 200) | "授权 Strava"不再调用全局 `_save()`，OneLap 凭证不会被保存 | 更新：此测试改为只验证 Strava Client ID/Secret 被保存，不再验证 OneLap 凭证 |
| `general save rejects invalid lookback days` (line 450) | 底部"保存"按钮已移除 | 删除此测试 |
| `general save failure shows error and no success state` (line 479) | 底部"保存"按钮已移除 | 删除此测试 |
| `general save keeps confirmed rewrite state in sync during toggle race` (line 658) | 底部"保存"按钮已移除 | 删除此测试 |
| `Strava save flows preserve rewrite switch value` (line 727) | 底部"保存"按钮已移除 | 删除此测试（GCJ 保留逻辑已有其他测试覆盖） |
| `Strava auth does not continue when general save is invalid` (line 759) | 行为变更：回溯天数无效不再阻塞 OAuth | 删除此测试（行为已变，测试前提不再成立） |

新增测试：
| 测试 | 描述 |
|------|------|
| `tapping upload to Strava toggle immediately persists setting` | 验证切换"上传到 Strava"开关后立即持久化 |
| `tapping upload to Xingzhe toggle immediately persists setting` | 验证切换"上传到 行者"开关后立即持久化 |
| `cannot turn off both upload platforms` | 验证两个平台不能同时关闭，显示提示 |
| `failed upload toggle persistence reverts switch and shows error` | 验证保存失败时回滚状态 |
| `rapid upload toggles persist the latest value` | 验证快速切换时防并发逻辑正确 |

## 验证

```bash
dart format --output=none --set-exit-if-changed lib
flutter analyze
flutter test
```
