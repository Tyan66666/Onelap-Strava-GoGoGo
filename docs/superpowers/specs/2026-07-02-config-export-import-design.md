# 配置文件导出与导入

## 概述

支持将应用设置导出为 JSON 文件，并从 JSON 文件导入设置，实现跨设备配置迁移。配置文件格式向后版本兼容。

## 决策记录

| 决策 | 选择 | 理由 |
|------|------|------|
| 导出范围 | 仅设置项（不含同步状态） | 配置迁移场景不需要历史数据 |
| 文件格式 | JSON | 结构清晰，易读易扩展 |
| 敏感数据 | 全部包含，导出时弹出风险提示 | 用户便利性优先 |
| 导入行为 | 完全覆盖当前设置 | 简单可预测 |
| 实现方案 | file_picker + share_plus | 标准跨平台 UX |

## 配置文件格式

```json
{
  "version": 1,
  "appVersion": "1.0.21",
  "exportedAt": "2026-07-02T10:00:00.000Z",
  "settings": {
    "onelap": {
      "username": "...",
      "password": "..."
    },
    "strava": {
      "uploadMode": "api",
      "clientId": "...",
      "clientSecret": "...",
      "refreshToken": "...",
      "accessToken": "...",
      "expiresAt": "...",
      "webCookies": "..."
    },
    "xingzhe": {
      "username": "...",
      "password": "...",
      "sessionId": "..."
    },
    "intervalsIcu": {
      "athleteId": "...",
      "apiKey": "..."
    },
    "sync": {
      "lookbackDays": 3,
      "gcjCorrectionEnabled": false,
      "uploadToStrava": true,
      "uploadToXingzhe": false,
      "uploadToIntervalsIcu": false
    }
  }
}
```

### 向后兼容规则

- `version` 字段标识格式版本，当前为 1
- 新版本仅追加字段，不删除或重命名已有字段
- 导入时忽略未知字段（前向兼容）
- 导入时缺失字段用默认值填充（后向兼容）

## UI 设计

在 `settings_screen.dart` 底部新增 **"配置文件管理"** 区域：

```
┌─────────────────────────────┐
│ 配置文件管理                 │
│                             │
│ [导出配置]         [导入配置] │
└─────────────────────────────┘
```

### 导出流程

1. 用户点击"导出配置"
2. 弹出确认对话框：提示"配置文件包含账号密码等敏感信息，请妥善保管"
3. 确认后，调用 `ConfigService.exportConfig()` 生成 JSON
4. 写入临时文件，调用 `Share.shareXFiles()` 系统分享

### 导入流程

1. 用户点击"导入配置"
2. 弹出确认对话框：提示"将覆盖所有当前设置，是否继续？"
3. 确认后，调用 `FilePicker.platform.pickFiles()` 选择文件
4. 读取文件内容，调用 `ConfigService.importConfig()` 解析并应用
5. 成功后显示 SnackBar"配置已导入"，页面刷新显示新设置
6. 失败时显示 SnackBar 错误信息

## 新增文件

### `lib/models/app_config.dart`

```dart
class AppConfig {
  final int version;
  final String appVersion;
  final String exportedAt;
  final Map<String, dynamic> settings;

  // toJson / fromJson
  // validate() — 校验 version 字段存在且为支持的版本
}
```

### `lib/services/config_service.dart`

```dart
class ConfigService {
  final SettingsService _settingsService;

  Future<String> exportConfig();      // 读取当前设置 → 构建 AppConfig → JSON
  Future<void> importConfig(String json);  // 解析 JSON → 校验 → 覆盖设置
}
```

## 新增依赖

```yaml
dependencies:
  file_picker: ^8.1.7
  share_plus: ^10.1.4
```

## 错误处理

| 场景 | 处理 |
|------|------|
| JSON 格式错误 | SnackBar "配置文件格式无效" |
| 缺少 `version` 字段 | SnackBar "配置文件格式无效：缺少版本信息" |
| 不支持的版本号 | SnackBar "配置文件版本不受支持" |
| 文件读取失败 | SnackBar "读取文件失败" |
| 导出时设置为空 | 正常导出（空值字段） |

## 测试策略

- `app_config_test.dart`：序列化/反序列化、版本校验、缺失字段默认值
- `config_service_test.dart`：导出完整覆盖所有 key、导入正确写入 SettingsService、导入错误格式抛异常
