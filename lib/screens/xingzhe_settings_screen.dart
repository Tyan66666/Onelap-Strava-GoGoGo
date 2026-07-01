import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/xingzhe_client.dart';

typedef ValidateXingzheLoginCallback =
    Future<void> Function(String username, String password);

class XingzheSettingsScreen extends StatefulWidget {
  const XingzheSettingsScreen({
    super.key,
    this.settingsService,
    this.validateXingzheLogin,
  });

  final SettingsService? settingsService;
  final ValidateXingzheLoginCallback? validateXingzheLogin;

  @override
  State<XingzheSettingsScreen> createState() => _XingzheSettingsScreenState();
}

class _XingzheSettingsScreenState extends State<XingzheSettingsScreen> {
  late final SettingsService _settingsService;
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  bool _savingXingzheCredentials = false;

  static const _controllerKeys = [
    SettingsService.keyXingzheUsername,
    SettingsService.keyXingzhePassword,
  ];

  static const _obscured = {SettingsService.keyXingzhePassword};

  static const _labels = {
    SettingsService.keyXingzheUsername: '行者 用户名',
    SettingsService.keyXingzhePassword: '行者 密码',
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
      _controllers[key]!.text = values[key] ?? '';
    }
    setState(() {
      _loading = false;
    });
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
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
      final ValidateXingzheLoginCallback validator =
          widget.validateXingzheLogin ??
          (String username, String password) {
            return XingzheClient.login(username: username, password: password);
          };
      await validator(effectiveUsername, effectivePassword);
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

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('行者 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
        ],
      ),
    );
  }
}
