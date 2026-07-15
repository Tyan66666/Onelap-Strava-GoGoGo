import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/settings_service.dart';

class OutbaseSettingsScreen extends StatefulWidget {
  const OutbaseSettingsScreen({super.key});

  @override
  State<OutbaseSettingsScreen> createState() => _OutbaseSettingsScreenState();
}

class _OutbaseSettingsScreenState extends State<OutbaseSettingsScreen> {
  late final SettingsService _settingsService;
  String? _sessionId;
  String? _loginTime;
  bool _loading = true;
  bool _webViewVisible = false;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final settings = await _settingsService.loadSettings();
    final id = settings[SettingsService.keyOutbaseSessionId];
    final loginTime = settings[SettingsService.keyOutbaseLoginTime];
    if (mounted) {
      setState(() {
        _sessionId = (id != null && id.isNotEmpty) ? id : null;
        _loginTime = (loginTime != null && loginTime.isNotEmpty)
            ? loginTime
            : null;
        _loading = false;
      });
    }
  }

  void _startLogin() {
    setState(() => _webViewVisible = true);
  }

  void _onSessionCaptured(String sessionId) async {
    debugPrint(
      'Outbase: captured sessionId=$sessionId (length=${sessionId.length})',
    );
    final now = DateTime.now().toIso8601String();
    await _settingsService.saveSettings({
      SettingsService.keyOutbaseSessionId: sessionId,
      SettingsService.keyUploadToOutbase: 'true',
      SettingsService.keyOutbaseLoginTime: now,
    });
    if (mounted) {
      setState(() {
        _sessionId = sessionId;
        _loginTime = now;
        _webViewVisible = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Outbase 登录成功')));
    }
  }

  void _logout() async {
    // 清除 WebView cookies
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    // 清除 secure storage
    await _settingsService.saveSettings({
      SettingsService.keyOutbaseSessionId: '',
      SettingsService.keyUploadToOutbase: 'false',
      SettingsService.keyOutbaseLoginTime: '',
    });
    if (mounted) {
      setState(() => _sessionId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已退出 Outbase 登录')));
    }
  }

  String _formatLoginTime(String iso8601) {
    try {
      final dt = DateTime.parse(iso8601).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso8601;
    }
  }

  bool _isSessionLikelyExpired(String iso8601) {
    try {
      final loginDt = DateTime.parse(iso8601);
      final now = DateTime.now().toUtc();
      return now.difference(loginDt.toUtc()).inDays >= 13; // 14天有效期，提前1天警告
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Outbase 设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_webViewVisible) {
      return _buildWebView();
    }

    if (_sessionId != null && _sessionId!.isNotEmpty) {
      return _buildLoggedIn();
    }

    return _buildNotLoggedIn();
  }

  Widget _buildWebView() {
    final controller = WebViewController();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) async {
            // 登录成功检测：URL 包含 dashboard.html 或 cookie 包含 sessionId（设计文档要求 OR 逻辑）
            final isDashboard = url.contains('dashboard.html');
            bool hasSessionId = false;

            try {
              final result = await controller.runJavaScriptReturningResult(
                'document.cookie',
              );
              final raw = result.toString();
              debugPrint('Outbase: raw cookie result: $raw');
              final match = RegExp(r'sessionId=([^;\s"]+)').firstMatch(raw);
              if (match != null) {
                final sessionId = match
                    .group(1)!
                    .replaceAll('"', '')
                    .replaceAll("'", '')
                    .replaceAll('\\', '')
                    .trim();
                debugPrint(
                  'Outbase: extracted sessionId=$sessionId '
                  '(length=${sessionId.length})',
                );
                if (sessionId.isNotEmpty && sessionId.length > 10) {
                  hasSessionId = true;
                  _onSessionCaptured(sessionId);
                }
              } else {
                debugPrint('Outbase: no sessionId match in cookie');
              }
            } catch (e) {
              debugPrint('Outbase: cookie extraction error: $e');
            }

            if (!isDashboard && !hasSessionId) {
              debugPrint(
                'Outbase: not dashboard URL and no sessionId found, url=$url',
              );
            }
          },
        ),
      )
      ..loadRequest(
        Uri.parse(
          'https://outbase.cn/zeusfit/official-website/dashboard.html?tab=import',
        ),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outbase 登录'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _webViewVisible = false),
            child: const Text('取消'),
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }

  Widget _buildLoggedIn() {
    return Scaffold(
      appBar: AppBar(title: const Text('Outbase 设置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[600],
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '已登录',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loginTime != null
                                ? '上次登录: ${_formatLoginTime(_loginTime!)}'
                                : 'Outbase 账号已连接',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          if (_loginTime != null &&
                              _isSessionLikelyExpired(_loginTime!))
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '⚠️ Session 可能已过期（14天有效期），建议重新登录',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _startLogin,
                icon: const Icon(Icons.refresh),
                label: const Text('重新登录'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('退出登录', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotLoggedIn() {
    return Scaffold(
      appBar: AppBar(title: const Text('Outbase 设置')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_upload_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              '未登录 Outbase',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '登录后可自动同步运动数据到 Outbase',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _startLogin,
              icon: const Icon(Icons.login),
              label: const Text('登录 Outbase'),
            ),
          ],
        ),
      ),
    );
  }
}
