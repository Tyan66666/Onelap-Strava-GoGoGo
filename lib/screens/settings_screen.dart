import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/onelap_client.dart';
import '../services/settings_service.dart';
import 'intervals_icu_settings_screen.dart';
import 'strava_settings_screen.dart';
import 'xingzhe_settings_screen.dart';

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
  bool _gcjCorrectionEnabled = false;
  bool _savingGcjCorrectionEnabled = false;
  bool? _pendingGcjCorrectionEnabled;
  bool _confirmedGcjCorrectionEnabled = false;
  bool _uploadToStrava = true;
  bool _uploadToXingzhe = false;
  bool _uploadToIntervalsIcu = false;
  bool _savingUploadToStrava = false;
  bool _savingUploadToXingzhe = false;
  bool _savingUploadToIntervalsIcu = false;
  bool? _pendingUploadToStrava;
  bool? _pendingUploadToXingzhe;
  bool? _pendingUploadToIntervalsIcu;
  bool _confirmedUploadToStrava = true;
  bool _confirmedUploadToXingzhe = false;
  bool _confirmedUploadToIntervalsIcu = false;

  static const _controllerKeys = [
    SettingsService.keyOneLapUsername,
    SettingsService.keyOneLapPassword,
    SettingsService.keyLookbackDays,
  ];

  static const _obscured = {SettingsService.keyOneLapPassword};

  static const _labels = {
    SettingsService.keyOneLapUsername: 'OneLap 用户名',
    SettingsService.keyOneLapPassword: 'OneLap 密码',
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
      _uploadToIntervalsIcu =
          values[SettingsService.keyUploadToIntervalsIcu] == 'true';
      _confirmedUploadToStrava = _uploadToStrava;
      _confirmedUploadToXingzhe = _uploadToXingzhe;
      _confirmedUploadToIntervalsIcu = _uploadToIntervalsIcu;
      _loading = false;
    });
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

  bool _otherPlatformsEnabled({
    required bool strava,
    required bool xingzhe,
    required bool intervalsIcu,
  }) {
    return strava || xingzhe || intervalsIcu;
  }

  Future<void> _toggleUploadToStrava(bool value) async {
    if (!value &&
        !_otherPlatformsEnabled(
          strava: false,
          xingzhe: _uploadToXingzhe,
          intervalsIcu: _uploadToIntervalsIcu,
        )) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少需要选择一个上传平台')));
      }
      return;
    }

    setState(() => _uploadToStrava = value);

    if (_savingUploadToStrava) {
      _pendingUploadToStrava = value;
      return;
    }

    _savingUploadToStrava = true;
    bool valueToPersist = value;

    while (true) {
      _pendingUploadToStrava = null;

      try {
        await _settingsService.saveSettings({
          SettingsService.keyUploadToStrava: valueToPersist.toString(),
        });
        _confirmedUploadToStrava = valueToPersist;
      } catch (e) {
        _savingUploadToStrava = false;
        _pendingUploadToStrava = null;
        if (mounted) {
          setState(() => _uploadToStrava = _confirmedUploadToStrava);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return;
      }

      final bool? pendingValue = _pendingUploadToStrava;
      if (pendingValue == null || pendingValue == valueToPersist) {
        _savingUploadToStrava = false;
        return;
      }

      valueToPersist = pendingValue;
    }
  }

  Future<void> _toggleUploadToXingzhe(bool value) async {
    if (!value &&
        !_otherPlatformsEnabled(
          strava: _uploadToStrava,
          xingzhe: false,
          intervalsIcu: _uploadToIntervalsIcu,
        )) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少需要选择一个上传平台')));
      }
      return;
    }

    setState(() => _uploadToXingzhe = value);

    if (_savingUploadToXingzhe) {
      _pendingUploadToXingzhe = value;
      return;
    }

    _savingUploadToXingzhe = true;
    bool valueToPersist = value;

    while (true) {
      _pendingUploadToXingzhe = null;

      try {
        await _settingsService.saveSettings({
          SettingsService.keyUploadToXingzhe: valueToPersist.toString(),
        });
        _confirmedUploadToXingzhe = valueToPersist;
      } catch (e) {
        _savingUploadToXingzhe = false;
        _pendingUploadToXingzhe = null;
        if (mounted) {
          setState(() => _uploadToXingzhe = _confirmedUploadToXingzhe);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return;
      }

      final bool? pendingValue = _pendingUploadToXingzhe;
      if (pendingValue == null || pendingValue == valueToPersist) {
        _savingUploadToXingzhe = false;
        return;
      }

      valueToPersist = pendingValue;
    }
  }

  Future<void> _toggleUploadToIntervalsIcu(bool value) async {
    if (!value &&
        !_otherPlatformsEnabled(
          strava: _uploadToStrava,
          xingzhe: _uploadToXingzhe,
          intervalsIcu: false,
        )) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('至少需要选择一个上传平台')));
      }
      return;
    }

    setState(() => _uploadToIntervalsIcu = value);

    if (_savingUploadToIntervalsIcu) {
      _pendingUploadToIntervalsIcu = value;
      return;
    }

    _savingUploadToIntervalsIcu = true;
    bool valueToPersist = value;

    while (true) {
      _pendingUploadToIntervalsIcu = null;

      try {
        await _settingsService.saveSettings({
          SettingsService.keyUploadToIntervalsIcu: valueToPersist.toString(),
        });
        _confirmedUploadToIntervalsIcu = valueToPersist;
      } catch (e) {
        _savingUploadToIntervalsIcu = false;
        _pendingUploadToIntervalsIcu = null;
        if (mounted) {
          setState(
            () => _uploadToIntervalsIcu = _confirmedUploadToIntervalsIcu,
          );
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
        }
        return;
      }

      final bool? pendingValue = _pendingUploadToIntervalsIcu;
      if (pendingValue == null || pendingValue == valueToPersist) {
        _savingUploadToIntervalsIcu = false;
        return;
      }

      valueToPersist = pendingValue;
    }
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

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildPlatformCard({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: value, onChanged: onChanged),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onTap,
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
            '同步平台',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          _buildPlatformCard(
            title: 'Strava',
            value: _uploadToStrava,
            onChanged: _toggleUploadToStrava,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StravaSettingsScreen(
                    settingsService: _settingsService,
                    authorizeStrava: widget.authorizeStrava,
                  ),
                ),
              );
            },
          ),
          _buildPlatformCard(
            title: '行者',
            value: _uploadToXingzhe,
            onChanged: _toggleUploadToXingzhe,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      XingzheSettingsScreen(settingsService: _settingsService),
                ),
              );
            },
          ),
          _buildPlatformCard(
            title: 'Intervals.icu',
            value: _uploadToIntervalsIcu,
            onChanged: _toggleUploadToIntervalsIcu,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => IntervalsIcuSettingsScreen(
                    settingsService: _settingsService,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
