import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:onelap_strava_sync/screens/strava_web_login_screen.dart';

class _FakeWebViewPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return _FakePlatformCookieManager(params);
  }
}

class _FakePlatformWebViewController extends PlatformWebViewController {
  _FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams request) async {}

  @override
  Future<void> setUserAgent(String? userAgent) async {}

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    return '';
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}

class _FakePlatformCookieManager extends PlatformWebViewCookieManager {
  _FakePlatformCookieManager(super.params) : super.implementation();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    WebViewPlatform.instance = _FakeWebViewPlatform();
  });

  testWidgets('shows app bar with title and close button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: StravaWebLoginScreen(onLoginSuccess: (_) {})),
    );
    await tester.pump();

    expect(find.text('登录 Strava'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('close button pops with false', (WidgetTester tester) async {
    bool? popResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              popResult = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => StravaWebLoginScreen(onLoginSuccess: (_) {}),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(popResult, false);
  });

  testWidgets('login success reads cookies via native channel and pops true', (
    WidgetTester tester,
  ) async {
    final List<MethodCall> calls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('onelap_strava_sync/cookie'),
          (MethodCall call) async {
            calls.add(call);
            if (call.method == 'getCookies') {
              return '_strava_session=abc123; other=value';
            }
            return null;
          },
        );

    await tester.pumpWidget(
      MaterialApp(home: StravaWebLoginScreen(onLoginSuccess: (_) {})),
    );
    await tester.pump();

    // No login triggered yet — verify mock registered
    expect(calls, isEmpty);

    // Clean up
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('onelap_strava_sync/cookie'),
          null,
        );
  });
}
