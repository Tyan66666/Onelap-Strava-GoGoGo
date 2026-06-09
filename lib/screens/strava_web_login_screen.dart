import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StravaWebLoginScreen extends StatefulWidget {
  final void Function(String cookies) onLoginSuccess;

  const StravaWebLoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<StravaWebLoginScreen> createState() => _StravaWebLoginScreenState();
}

class _StravaWebLoginScreenState extends State<StravaWebLoginScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _didComplete = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.parse(request.url);
            if (uri.path.contains('/dashboard') ||
                uri.path.contains('/athlete')) {
              _handleLoginSuccess();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!_didComplete && mounted && error.isForMainFrame == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('页面加载失败: ${error.description}'),
                  action: SnackBarAction(
                    label: '重试',
                    onPressed: () => _controller.reload(),
                  ),
                ),
              );
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.strava.com/login'));
  }

  static const _cookieChannel = MethodChannel('onelap_strava_sync/cookie');

  Future<void> _handleLoginSuccess() async {
    if (_didComplete) return;
    _didComplete = true;

    String cookieString;
    try {
      cookieString = await _cookieChannel.invokeMethod<String>(
        'getCookies',
        'https://www.strava.com',
      ) ?? '';
    } catch (_) {
      final result = await _controller.runJavaScriptReturningResult(
        'document.cookie',
      );
      cookieString = result.toString();
    }

    if (mounted) {
      widget.onLoginSuccess(cookieString);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录 Strava'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
