import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/settings_service.dart';
import 'strava_auth_screen.dart';
import 'strava_web_login_screen.dart';

typedef AuthorizeStravaCallback =
    Future<bool?> Function(String clientId, String clientSecret);

class StravaSettingsScreen extends StatefulWidget {
  const StravaSettingsScreen({
    super.key,
    this.settingsService,
    this.authorizeStrava,
  });

  final SettingsService? settingsService;
  final AuthorizeStravaCallback? authorizeStrava;

  @override
  State<StravaSettingsScreen> createState() => _StravaSettingsScreenState();
}

class _StravaSettingsScreenState extends State<StravaSettingsScreen> {
  late final SettingsService _settingsService;
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  String _stravaUploadMode = 'api';

  static const _controllerKeys = [
    SettingsService.keyStravaClientId,
    SettingsService.keyStravaClientSecret,
    SettingsService.keyStravaRefreshToken,
    SettingsService.keyStravaAccessToken,
    SettingsService.keyStravaExpiresAt,
    SettingsService.keyStravaWebCookies,
  ];

  static const _obscured = {SettingsService.keyStravaClientSecret};

  static const _labels = {
    SettingsService.keyStravaClientId: 'Client ID（客户端ID）',
    SettingsService.keyStravaClientSecret: 'Client Secret（客户端密钥）',
    SettingsService.keyStravaAccessToken: 'Access Token（访问令牌）',
    SettingsService.keyStravaRefreshToken: 'Refresh Token（刷新令牌）',
    SettingsService.keyStravaExpiresAt: 'Expires At（过期时间，Unix 时间戳）',
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
      _stravaUploadMode = values[SettingsService.keyStravaUploadMode] == 'web'
          ? 'web'
          : 'api';
      _loading = false;
    });
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

    try {
      await _settingsService.saveSettings({
        SettingsService.keyStravaClientId: clientId,
        SettingsService.keyStravaClientSecret: clientSecret,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设置保存失败: $e')));
      }
      return;
    }

    // ignore: use_build_context_synchronously
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
                '3. 创建后复制 Client ID（客户端ID）和 Client Secret（客户端密钥）填入此处\n'
                '4. 点击"授权 Strava"按钮完成授权，Access Token（访问令牌）、Refresh Token（刷新令牌）和 Expires At 将自动填入',
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
      appBar: AppBar(title: const Text('Strava 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('上传方式', style: TextStyle(fontSize: 14)),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'api', label: Text('API')),
              ButtonSegment(value: 'web', label: Text('网页')),
            ],
            selected: {_stravaUploadMode},
            onSelectionChanged: (selection) {
              final mode = selection.first;
              setState(() => _stravaUploadMode = mode);
              _settingsService.saveSettings({
                SettingsService.keyStravaUploadMode: mode,
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _stravaUploadMode == 'api'
                ? '推荐使用 API 方式，最稳定。2026 年 7 月起 Strava API 将需要会员订阅，届时可切换到网页上传。'
                : '网页上传通过模拟浏览器登录 Strava，无需 API 凭证。',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_stravaUploadMode == 'api') ...[
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
              SettingsService.keyStravaAccessToken,
              SettingsService.keyStravaRefreshToken,
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
          ] else ...[
            const Text(
              'Strava 网页登录',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _controllers[SettingsService.keyStravaWebCookies]!.text.isNotEmpty
                  ? '已登录'
                  : '未登录',
              style: TextStyle(
                color:
                    _controllers[SettingsService.keyStravaWebCookies]!
                        .text
                        .isNotEmpty
                    ? Colors.green
                    : Colors.red,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => StravaWebLoginScreen(
                      onLoginSuccess: (cookies) async {
                        await _settingsService.saveSettings({
                          SettingsService.keyStravaWebCookies: cookies,
                        });
                      },
                    ),
                  ),
                );
                if (result == true && mounted) {
                  await _load();
                  if (mounted) {
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Strava 登录成功')),
                    );
                  }
                }
              },
              child: const Text('登录 Strava'),
            ),
          ],
        ],
      ),
    );
  }
}
