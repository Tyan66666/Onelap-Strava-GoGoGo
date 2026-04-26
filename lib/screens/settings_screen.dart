import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/onelap_client.dart';
import '../services/settings_service.dart';
import '../services/xingzhe_client.dart';
import 'strava_auth_screen.dart';

typedef AuthorizeStravaCallback =
    Future<bool?> Function(String clientId, String clientSecret);
typedef ValidateOneLapLoginCallback =
    Future<void> Function(String username, String password);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.settingsService,
    this.authorizeStrava,
    this.validateOneLapLogin,
  });

  final SettingsService? settingsService;
  final AuthorizeStravaCallback? authorizeStrava;
  final ValidateOneLapLoginCallback? validateOneLapLogin;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsService _settingsService;
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  bool _savingOneLapCredentials = false;
  bool _savingXingzheCredentials = false;
  bool _gcjCorrectionEnabled = false;
  bool _savingGcjCorrectionEnabled = false;
  bool? _pendingGcjCorrectionEnabled;
  bool _confirmedGcjCorrectionEnabled = false;
  bool _uploadToStrava = true;
  bool _uploadToXingzhe = false;
  bool _savingUploadSettings = false;

  static const _controllerKeys = [
    SettingsService.keyOneLapUsername,
    SettingsService.keyOneLapPassword,
    SettingsService.keyStravaClientId,
    SettingsService.keyStravaClientSecret,
    SettingsService.keyStravaRefreshToken,
    SettingsService.keyStravaAccessToken,
    SettingsService.keyStravaExpiresAt,
    SettingsService.keyXingzheUsername,
    SettingsService.keyXingzhePassword,
    SettingsService.keyLookbackDays,
  ];

  static const _obscured = {
    SettingsService.keyOneLapPassword,
    SettingsService.keyStravaClientSecret,
    SettingsService.keyXingzhePassword,
  };

  static const _labels = {
    SettingsService.keyOneLapUsername: 'OneLap 用户名',
    SettingsService.keyOneLapPassword: 'OneLap 密码',
    SettingsService.keyStravaClientId: 'Strava Client ID',
    SettingsService.keyStravaClientSecret: 'Strava Client Secret',
    SettingsService.keyStravaRefreshToken: 'Strava Refresh Token',
    SettingsService.keyStravaAccessToken: 'Strava Access Token',
    SettingsService.keyStravaExpiresAt: 'Strava Expires At (Unix timestamp)',
    SettingsService.keyXingzheUsername: '行者 用户名',
    SettingsService.keyXingzhePassword: '行者 密码',
    SettingsService.keyLookbackDays: '同步最近几天（默认 3）',
  };

  @override
  void initState() {
    super.initState();
    _settingsService = widget.settingsService ?? SettingsService();
    for (final key in _controllerKeys) {
      _controllers[key] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final values = await _settingsService.loadSettings();
    if (!mounted) {
      return;
    }
    for (final key in _controllerKeys) {
      _controllers[key]!.text = key == SettingsService.keyLookbackDays
          ? (values[key]?.isNotEmpty == true ? values[key]! : '3')
          : values[key] ?? '';
    }
    setState(() {
      _gcjCorrectionEnabled =
          values[SettingsService.keyGcjCorrectionEnabled] == 'true';
      _confirmedGcjCorrectionEnabled = _gcjCorrectionEnabled;
      _uploadToStrava = values[SettingsService.keyUploadToStrava] != 'false';
      _uploadToXingzhe = values[SettingsService.keyUploadToXingzhe] == 'true';
      _loading = false;
    });
  }

  Future<bool> _save() async {
    final String? lookbackDays = _validatedLookbackDays();
    if (lookbackDays == null) {
      return false;
    }

    final values = {
      for (final key in _controllerKeys) key: _controllers[key]!.text.trim(),
      SettingsService.keyLookbackDays: lookbackDays,
      SettingsService.keyGcjCorrectionEnabled: _gcjCorrectionEnabled.toString(),
      SettingsService.keyUploadToStrava: _uploadToStrava.toString(),
      SettingsService.keyUploadToXingzhe: _uploadToXingzhe.toString(),
    };
    try {
      await _settingsService.saveSettings(values);
      _confirmedGcjCorrectionEnabled = _gcjCorrectionEnabled;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置已保存')));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
      }
      return false;
    }
  }

  Future<void> _saveOneLapCredentials({bool validateAfterSave = false}) async {
    _dismissKeyboard();

    final Map<String, String> values = {
      SettingsService.keyOneLapUsername:
          _controllers[SettingsService.keyOneLapUsername]!.text.trim(),
      SettingsService.keyOneLapPassword:
          _controllers[SettingsService.keyOneLapPassword]!.text.trim(),
    };
    if (validateAfterSave) {
      if (mounted) {
        setState(() => _savingOneLapCredentials = true);
      }
      try {
        final bool success = await _validateOneLapLogin(
          username: values[SettingsService.keyOneLapUsername]!,
          password: values[SettingsService.keyOneLapPassword]!,
          persistValues: values,
          showSuccessMessage: false,
        );
        if (success && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('OneLap 账号已保存')));
        }
      } finally {
        if (mounted) {
          setState(() => _savingOneLapCredentials = false);
        }
      }
      return;
    }
    await _settingsService.saveSettings(values);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OneLap 账号已保存')));
    }
  }

  Future<void> _saveXingzheCredentials({bool validateAfterSave = false}) async {
    _dismissKeyboard();

    final Map<String, String> values = {
      SettingsService.keyXingzheUsername:
          _controllers[SettingsService.keyXingzheUsername]!.text.trim(),
      SettingsService.keyXingzhePassword:
          _controllers[SettingsService.keyXingzhePassword]!.text.trim(),
    };
    if (validateAfterSave) {
      if (mounted) {
        setState(() => _savingXingzheCredentials = true);
      }
      try {
        final bool success = await _validateXingzheLogin(
          username: values[SettingsService.keyXingzheUsername]!,
          password: values[SettingsService.keyXingzhePassword]!,
          persistValues: values,
          showSuccessMessage: false,
        );
        if (success && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('行者账号已保存')));
        }
      } finally {
        if (mounted) {
          setState(() => _savingXingzheCredentials = false);
        }
      }
      return;
    }
    await _settingsService.saveSettings(values);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行者账号已保存')));
    }
  }

  Future<bool> _validateOneLapLogin({
    String? username,
    String? password,
    Map<String, String>? persistValues,
    bool showSuccessMessage = true,
  }) async {
    final effectiveUsername =
        username ??
        _controllers[SettingsService.keyOneLapUsername]!.text.trim();
    final effectivePassword =
        password ??
        _controllers[SettingsService.keyOneLapPassword]!.text.trim();

    if (effectiveUsername.isEmpty || effectivePassword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先填写 OneLap 用户名和密码')));
      }
      return false;
    }

    try {
      final ValidateOneLapLoginCallback validator =
          widget.validateOneLapLogin ??
          (String username, String password) {
            final client = OneLapClient(
              baseUrl: 'https://www.onelap.cn',
              username: username,
              password: password,
            );
            return client.login();
          };
      await validator(effectiveUsername, effectivePassword);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('OneLap 登录验证失败: $e')));
      }
      return false;
    }

    if (persistValues != null) {
      try {
        await _settingsService.saveSettings(persistValues);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return false;
      }
    }

    if (mounted && showSuccessMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OneLap 登录验证成功')));
    }
    return true;
  }

  Future<bool> _validateXingzheLogin({
    String? username,
    String? password,
    Map<String, String>? persistValues,
    bool showSuccessMessage = true,
  }) async {
    final effectiveUsername =
        username ??
        _controllers[SettingsService.keyXingzheUsername]!.text.trim();
    final effectivePassword =
        password ??
        _controllers[SettingsService.keyXingzhePassword]!.text.trim();

    if (effectiveUsername.isEmpty || effectivePassword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先填写行者用户名和密码')));
      }
      return false;
    }

    try {
      await XingzheClient.login(
        username: effectiveUsername,
        password: effectivePassword,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('行者登录验证失败: $e')));
      }
      return false;
    }

    if (persistValues != null) {
      try {
        await _settingsService.saveSettings(persistValues);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return false;
      }
    }

    if (mounted && showSuccessMessage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('行者登录验证成功')));
    }
    return true;
  }

  Future<void> _saveSyncSettings() async {
    _dismissKeyboard();

    final String? lookbackDays = _validatedLookbackDays();
    if (lookbackDays == null) {
      return;
    }

    try {
      await _settingsService.saveSettings({
        SettingsService.keyLookbackDays: lookbackDays,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('同步设置已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
      }
    }
  }

  Future<void> _saveGcjCorrectionEnabled(bool value) async {
    if (value == _gcjCorrectionEnabled &&
        !_savingGcjCorrectionEnabled &&
        _pendingGcjCorrectionEnabled == null) {
      return;
    }

    setState(() => _gcjCorrectionEnabled = value);

    if (_savingGcjCorrectionEnabled) {
      _pendingGcjCorrectionEnabled = value;
      return;
    }

    _savingGcjCorrectionEnabled = true;
    bool valueToPersist = value;

    while (true) {
      _pendingGcjCorrectionEnabled = null;

      try {
        await _settingsService.saveSettings({
          SettingsService.keyGcjCorrectionEnabled: valueToPersist.toString(),
        });
        _confirmedGcjCorrectionEnabled = valueToPersist;
      } catch (e) {
        _savingGcjCorrectionEnabled = false;
        _pendingGcjCorrectionEnabled = null;
        if (mounted) {
          setState(
            () => _gcjCorrectionEnabled = _confirmedGcjCorrectionEnabled,
          );
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return;
      }

      final bool? pendingValue = _pendingGcjCorrectionEnabled;
      if (pendingValue == null || pendingValue == valueToPersist) {
        _savingGcjCorrectionEnabled = false;
        return;
      }

      valueToPersist = pendingValue;
    }
  }

  Future<void> _saveUploadSettings() async {
    _dismissKeyboard();

    if (!_uploadToStrava && !_uploadToXingzhe) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少需要选择一个上传平台')));
      }
      return;
    }

    _savingUploadSettings = true;
    try {
      await _settingsService.saveSettings({
        SettingsService.keyUploadToStrava: _uploadToStrava.toString(),
        SettingsService.keyUploadToXingzhe: _uploadToXingzhe.toString(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('上传设置已保存')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
      }
    } finally {
      _savingUploadSettings = false;
    }
  }

  void _toggleUploadToStrava(bool value) {
    setState(() => _uploadToStrava = value);
  }

  void _toggleUploadToXingzhe(bool value) {
    setState(() => _uploadToXingzhe = value);
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  String? _validatedLookbackDays() {
    final String lookbackDays = _controllers[SettingsService.keyLookbackDays]!
        .text
        .trim();
    final int? parsedLookbackDays = int.tryParse(lookbackDays);
    if (parsedLookbackDays == null || parsedLookbackDays <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入大于 0 的整数天数')));
      }
      return null;
    }
    return lookbackDays;
  }

  Future<void> _authorizeStrava() async {
    final clientId = _controllers[SettingsService.keyStravaClientId]!.text
        .trim();
    final clientSecret = _controllers[SettingsService.keyStravaClientSecret]!
        .text
        .trim();

    if (clientId.isEmpty || clientSecret.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先填写 Strava Client ID 和 Client Secret'),
          ),
        );
      }
      return;
    }

    final bool saved = await _save();
    if (!mounted) return;
    if (!saved) return;

    final navigator = Navigator.of(context);

    final result =
        await (widget.authorizeStrava?.call(clientId, clientSecret) ??
            navigator.push<bool>(
              MaterialPageRoute(
                builder: (_) => StravaAuthScreen(
                  clientId: clientId,
                  clientSecret: clientSecret,
                ),
              ),
            ));

    if (!mounted) return;

    if (result == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Strava 授权成功')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('授权取消或失败')));
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _showStravaApiInfo() {
    const stravaApiUrl = 'https://www.strava.com/settings/api';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于 Strava API 凭证'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Strava 对个人开发者的 API 访问有严格限制，每个应用每 15 分钟最多 200 次请求、每天 2000 次。\n\n'
                '为了不让所有用户共享同一个配额，本应用需要你使用自己的 Strava API 应用凭证。\n\n'
                '注册步骤：',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(stravaApiUrl),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  '1. 登录 https://www.strava.com/settings/api',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              const Text(
                '2. 创建一个新应用，"Authorization Callback Domain" 填写 localhost\n'
                '3. 创建后复制 Client ID 和 Client Secret 填入此处\n'
                '4. 点击"授权 Strava"按钮完成授权，Access Token、Refresh Token 和 Expires At 将自动填入',
                style: TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'OneLap 账号',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final key in [
            SettingsService.keyOneLapUsername,
            SettingsService.keyOneLapPassword,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllers[key],
                obscureText: _obscured.contains(key),
                decoration: InputDecoration(
                  labelText: _labels[key],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _savingOneLapCredentials
                      ? null
                      : () => _saveOneLapCredentials(validateAfterSave: true),
                  child: _savingOneLapCredentials
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('验证中...'),
                          ],
                        )
                      : const Text('保存 OneLap 账号'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '同步设置',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('上传前将 GCJ-02 转为 WGS84'),
            subtitle: const Text('仅在来源轨迹偏移且确认使用 GCJ-02 时开启'),
            value: _gcjCorrectionEnabled,
            onChanged: _saveGcjCorrectionEnabled,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _controllers[SettingsService.keyLookbackDays],
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveSyncSettings(),
              decoration: InputDecoration(
                labelText: _labels[SettingsService.keyLookbackDays],
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: _saveSyncSettings,
            child: const Text('保存同步设置'),
          ),
          const SizedBox(height: 16),
          const Text(
            '上传设置',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('上传到 Strava'),
            value: _uploadToStrava,
            onChanged: _toggleUploadToStrava,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('上传到 行者'),
            value: _uploadToXingzhe,
            onChanged: _toggleUploadToXingzhe,
          ),
          ElevatedButton(
            onPressed: _saveUploadSettings,
            child: _savingUploadSettings
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('保存中...'),
                    ],
                  )
                : const Text('保存上传设置'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Strava 凭证',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '为什么需要填写 Strava 凭证？',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: '查看说明',
                onPressed: _showStravaApiInfo,
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: _authorizeStrava,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('授权 Strava'),
          ),
          const SizedBox(height: 12),
          for (final key in [
            SettingsService.keyStravaClientId,
            SettingsService.keyStravaClientSecret,
            SettingsService.keyStravaRefreshToken,
            SettingsService.keyStravaAccessToken,
            SettingsService.keyStravaExpiresAt,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllers[key],
                obscureText: _obscured.contains(key),
                decoration: InputDecoration(
                  labelText: _labels[key],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            '行者 凭证',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final key in [
            SettingsService.keyXingzheUsername,
            SettingsService.keyXingzhePassword,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllers[key],
                obscureText: _obscured.contains(key),
                decoration: InputDecoration(
                  labelText: _labels[key],
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _savingXingzheCredentials
                      ? null
                      : () => _saveXingzheCredentials(validateAfterSave: true),
                  child: _savingXingzheCredentials
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('登录中...'),
                          ],
                        )
                      : const Text('登录 行者'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}
