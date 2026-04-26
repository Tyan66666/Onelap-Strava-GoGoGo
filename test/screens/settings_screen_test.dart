import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/screens/settings_screen.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, String>? initialValues])
    : _values = Map<String, String>.from(initialValues ?? <String, String>{});

  final Map<String, String> _values;

  @override
  Future<Map<String, String>> readAll() async {
    return Map<String, String>.from(_values);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}

class ThrowOnWriteSettingsStore extends InMemorySettingsStore {
  ThrowOnWriteSettingsStore([super.initialValues]);

  @override
  Future<void> write({required String key, required String value}) {
    throw Exception('save failed');
  }
}

class DelayedReadSettingsStore extends InMemorySettingsStore {
  DelayedReadSettingsStore(this._readCompleter, [super.initialValues]);

  final Completer<void> _readCompleter;

  @override
  Future<Map<String, String>> readAll() async {
    await _readCompleter.future;
    return super.readAll();
  }
}

class PendingWrite {
  PendingWrite({
    required this.key,
    required this.value,
    required this.completer,
  });

  final String key;
  final String value;
  final Completer<void> completer;
}

class ControlledWriteSettingsStore extends InMemorySettingsStore {
  ControlledWriteSettingsStore([super.initialValues]);

  final List<PendingWrite> writes = <PendingWrite>[];

  @override
  Future<void> write({required String key, required String value}) {
    final Completer<void> completer = Completer<void>();
    writes.add(PendingWrite(key: key, value: value, completer: completer));
    return completer.future.then((_) {
      _values[key] = value;
    });
  }
}

class FailControlledWriteSettingsStore extends ControlledWriteSettingsStore {
  FailControlledWriteSettingsStore([super.initialValues]);

  final Set<int> failingWriteIndexes = <int>{};

  @override
  Future<void> write({required String key, required String value}) {
    final int writeIndex = writes.length;
    final Completer<void> completer = Completer<void>();
    writes.add(PendingWrite(key: key, value: value, completer: completer));
    return completer.future.then((_) {
      if (failingWriteIndexes.contains(writeIndex)) {
        throw Exception('save failed');
      }
      _values[key] = value;
    });
  }
}

class CrossSaveRaceSettingsStore extends InMemorySettingsStore {
  CrossSaveRaceSettingsStore([super.initialValues]);

  Completer<void>? firstGcjWriteCompleter;
  bool failFirstGcjWrite = false;
  int _gcjWriteCount = 0;

  @override
  Future<void> write({required String key, required String value}) {
    if (key != SettingsService.keyGcjCorrectionEnabled) {
      _values[key] = value;
      return Future<void>.value();
    }

    if (_gcjWriteCount == 0) {
      _gcjWriteCount++;
      firstGcjWriteCompleter = Completer<void>();
      return firstGcjWriteCompleter!.future.then((_) {
        if (failFirstGcjWrite) {
          throw Exception('save failed');
        }
        _values[key] = value;
      });
    }

    _gcjWriteCount++;
    _values[key] = value;
    return Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Finder fieldWithLabel(String labelText) {
    return find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == labelText,
      description: 'TextField($labelText)',
    );
  }

  void useLargeTestViewport(WidgetTester tester) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> enterVisibleText(
    WidgetTester tester,
    String labelText,
    String value,
  ) async {
    final Finder field = fieldWithLabel(labelText);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }

  Finder buttonWithText(String text) {
    final Finder elevated = find.widgetWithText(ElevatedButton, text);
    if (elevated.evaluate().isNotEmpty) {
      return elevated;
    }

    final Finder outlined = find.widgetWithText(OutlinedButton, text);
    if (outlined.evaluate().isNotEmpty) {
      return outlined;
    }

    return find.text(text);
  }

  Finder gcjCorrectionSwitch() {
    return find.descendant(
      of: find.widgetWithText(SwitchListTile, '上传前将 GCJ-02 转为 WGS84'),
      matching: find.byType(Switch),
    );
  }

  Future<void> tapVisibleText(WidgetTester tester, String text) async {
    final Finder target = buttonWithText(text);
    await tester.ensureVisible(target);
    await tester.tap(target, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  bool hasFocusedEditableText(WidgetTester tester) {
    return find
        .byType(EditableText)
        .evaluate()
        .map(
          (element) =>
              tester.widget<EditableText>(find.byWidget(element.widget)),
        )
        .any((editableText) => editableText.focusNode.hasFocus);
  }

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('preserves entered credentials after successful Strava auth', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authorizeStrava: (String clientId, String clientSecret) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'OneLap 用户名', 'rider@example.com');
    await enterVisibleText(tester, 'OneLap 密码', 'onelap-pass');
    await enterVisibleText(tester, 'Strava Client ID', '12345');
    await enterVisibleText(tester, 'Strava Client Secret', 'secret-xyz');

    await tapVisibleText(tester, '授权 Strava');

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyOneLapUsername], 'rider@example.com');
    expect(settings[SettingsService.keyOneLapPassword], 'onelap-pass');
    expect(settings[SettingsService.keyStravaClientId], '12345');
    expect(settings[SettingsService.keyStravaClientSecret], 'secret-xyz');
  });

  testWidgets('save OneLap credentials validates and persists on success', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyStravaClientId: 'stored-client-id',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          validateOneLapLogin: (String username, String password) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'OneLap 用户名', 'solo-user');
    await enterVisibleText(tester, 'OneLap 密码', 'solo-pass');

    await tapVisibleText(tester, '保存 OneLap 账号');

    expect(find.text('OneLap 账号已保存'), findsOneWidget);

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyOneLapUsername], 'solo-user');
    expect(settings[SettingsService.keyOneLapPassword], 'solo-pass');
    expect(settings[SettingsService.keyStravaClientId], 'stored-client-id');
  });

  testWidgets('save OneLap credentials also validates current input', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    String? validatedUsername;
    String? validatedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          validateOneLapLogin: (String username, String password) async {
            validatedUsername = username;
            validatedPassword = password;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'OneLap 用户名', 'verify-user');
    await enterVisibleText(tester, 'OneLap 密码', 'verify-pass');

    await tapVisibleText(tester, '保存 OneLap 账号');

    expect(validatedUsername, 'verify-user');
    expect(validatedPassword, 'verify-pass');

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyOneLapUsername], 'verify-user');
    expect(settings[SettingsService.keyOneLapPassword], 'verify-pass');
  });

  testWidgets(
    'save OneLap credentials shows validating state while request is in flight',
    (WidgetTester tester) async {
      useLargeTestViewport(tester);

      final Completer<void> validationCompleter = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            validateOneLapLogin: (String username, String password) {
              return validationCompleter.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await enterVisibleText(tester, 'OneLap 用户名', 'slow-user');
      await enterVisibleText(tester, 'OneLap 密码', 'slow-pass');

      await tester.tap(buttonWithText('保存 OneLap 账号'));
      await tester.pump();

      expect(find.text('验证中...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final ElevatedButton button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '验证中...'),
      );
      expect(button.onPressed, isNull);

      validationCompleter.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed OneLap validation keeps previous credentials and restores idle state',
    (WidgetTester tester) async {
      useLargeTestViewport(tester);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SettingsService.keyOneLapUsername: 'stable-user',
        SettingsService.keyOneLapPassword: 'stable-pass',
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            validateOneLapLogin: (String username, String password) async {
              throw Exception('invalid credentials');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await enterVisibleText(tester, 'OneLap 用户名', 'wrong-user');
      await enterVisibleText(tester, 'OneLap 密码', 'wrong-pass');

      await tapVisibleText(tester, '保存 OneLap 账号');

      expect(
        find.text('OneLap 登录验证失败: Exception: invalid credentials'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('OneLap 账号已保存'), findsNothing);
      expect(find.text('保存 OneLap 账号'), findsOneWidget);
      expect(find.text('验证中...'), findsNothing);

      final Map<String, String> settings = await SettingsService()
          .loadSettings();
      expect(settings[SettingsService.keyOneLapUsername], 'stable-user');
      expect(settings[SettingsService.keyOneLapPassword], 'stable-pass');
    },
  );

  testWidgets('empty OneLap credentials do not show saved success state', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          validateOneLapLogin: (String username, String password) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tapVisibleText(tester, '保存 OneLap 账号');

    expect(find.text('请先填写 OneLap 用户名和密码'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text('OneLap 账号已保存'), findsNothing);
  });

  testWidgets('persistence failure after OneLap validation shows save error', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final SettingsService settingsService = SettingsService(
      store: ThrowOnWriteSettingsStore(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settingsService: settingsService,
          validateOneLapLogin: (String username, String password) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'OneLap 用户名', 'persist-user');
    await enterVisibleText(tester, 'OneLap 密码', 'persist-pass');

    await tapVisibleText(tester, '保存 OneLap 账号');

    expect(find.text('设置保存失败: Exception: save failed'), findsOneWidget);
    expect(find.text('OneLap 登录验证失败: Exception: save failed'), findsNothing);
    expect(find.text('OneLap 账号已保存'), findsNothing);
  });

  testWidgets('save sync settings persists lookback days only', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyOneLapUsername: 'stable-user',
      SettingsService.keyLookbackDays: '3',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await enterVisibleText(tester, '同步最近几天（默认 3）', '7');

    await tapVisibleText(tester, '保存同步设置');

    expect(find.text('同步设置已保存'), findsOneWidget);

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '7');
    expect(settings[SettingsService.keyOneLapUsername], 'stable-user');
  });

  testWidgets('general save rejects invalid lookback days', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
      SettingsService.keyStravaClientId: 'stable-client-id',
      SettingsService.keyLookbackDays: '3',
    });
    final SettingsService settingsService = SettingsService(store: store);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'Strava Client ID', 'new-client-id');
    await enterVisibleText(tester, '同步最近几天（默认 3）', '0');

    await tapVisibleText(tester, '保存');

    expect(find.text('请输入大于 0 的整数天数'), findsOneWidget);
    expect(find.text('设置已保存'), findsNothing);

    final Map<String, String> settings = await settingsService.loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '3');
    expect(settings[SettingsService.keyStravaClientId], 'stable-client-id');
  });

  testWidgets('general save failure shows error and no success state', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final SettingsService settingsService = SettingsService(
      store: ThrowOnWriteSettingsStore(<String, String>{
        SettingsService.keyLookbackDays: '3',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'Strava Client ID', 'client-id');
    await tapVisibleText(tester, '保存');

    expect(find.text('设置保存失败: Exception: save failed'), findsOneWidget);
    expect(find.text('设置已保存'), findsNothing);
  });

  testWidgets('rewrite switch loads from stored settings', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyGcjCorrectionEnabled: 'true',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('上传前将 GCJ-02 转为 WGS84'), findsOneWidget);
    expect(find.text('仅在来源轨迹偏移且确认使用 GCJ-02 时开启'), findsOneWidget);

    final Switch rewriteSwitch = tester.widget<Switch>(gcjCorrectionSwitch());
    expect(rewriteSwitch.value, isTrue);
  });

  testWidgets('toggling rewrite switch and saving sync settings persists it', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyLookbackDays: '3',
      SettingsService.keyGcjCorrectionEnabled: 'false',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(gcjCorrectionSwitch());
    await tester.tap(gcjCorrectionSwitch());
    await tester.pumpAndSettle();

    await enterVisibleText(tester, '同步最近几天（默认 3）', '7');
    await tapVisibleText(tester, '保存同步设置');

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '7');
    expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
  });

  testWidgets('tapping rewrite switch immediately persists GCJ setting', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
      SettingsService.keyGcjCorrectionEnabled: 'false',
      SettingsService.keyLookbackDays: '3',
    });
    final SettingsService settingsService = SettingsService(store: store);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(gcjCorrectionSwitch());
    await tester.tap(gcjCorrectionSwitch());
    await tester.pumpAndSettle();

    final Map<String, String> settings = await settingsService.loadSettings();
    expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
    expect(settings[SettingsService.keyLookbackDays], '3');
  });

  testWidgets('rapid rewrite toggles persist the latest value in order', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final ControlledWriteSettingsStore store =
        ControlledWriteSettingsStore(<String, String>{
          SettingsService.keyGcjCorrectionEnabled: 'false',
          SettingsService.keyLookbackDays: '3',
        });
    final SettingsService settingsService = SettingsService(store: store);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(gcjCorrectionSwitch());
    await tester.tap(gcjCorrectionSwitch());
    await tester.pump();

    expect(store.writes, hasLength(1));
    expect(store.writes[0].key, SettingsService.keyGcjCorrectionEnabled);
    expect(store.writes[0].value, 'true');

    await tester.tap(gcjCorrectionSwitch());
    await tester.pump();

    final Switch rewriteSwitch = tester.widget<Switch>(gcjCorrectionSwitch());
    expect(rewriteSwitch.value, isFalse);
    expect(store.writes, hasLength(1));

    store.writes[0].completer.complete();
    await tester.pump();

    expect(store.writes, hasLength(2));
    expect(store.writes[1].key, SettingsService.keyGcjCorrectionEnabled);
    expect(store.writes[1].value, 'false');

    store.writes[1].completer.complete();
    await tester.pumpAndSettle();

    final Map<String, String> settings = await settingsService.loadSettings();
    expect(settings[SettingsService.keyGcjCorrectionEnabled], 'false');
  });

  testWidgets(
    'failed queued rewrite save falls back to last confirmed persisted state',
    (WidgetTester tester) async {
      useLargeTestViewport(tester);

      final FailControlledWriteSettingsStore store =
          FailControlledWriteSettingsStore(<String, String>{
            SettingsService.keyGcjCorrectionEnabled: 'false',
            SettingsService.keyLookbackDays: '3',
          });
      final SettingsService settingsService = SettingsService(store: store);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsService: settingsService)),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(gcjCorrectionSwitch());
      await tester.tap(gcjCorrectionSwitch());
      await tester.pump();

      await tester.tap(gcjCorrectionSwitch());
      await tester.pump();

      store.writes[0].completer.complete();
      await tester.pump();

      expect(store.writes, hasLength(2));
      store.failingWriteIndexes.add(1);
      store.writes[1].completer.complete();
      await tester.pumpAndSettle();

      final Switch rewriteSwitch = tester.widget<Switch>(gcjCorrectionSwitch());
      expect(rewriteSwitch.value, isTrue);
      expect(find.text('设置保存失败: Exception: save failed'), findsOneWidget);

      final Map<String, String> settings = await settingsService.loadSettings();
      expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
    },
  );

  testWidgets(
    'general save keeps confirmed rewrite state in sync during toggle race',
    (WidgetTester tester) async {
      useLargeTestViewport(tester);

      final CrossSaveRaceSettingsStore store =
          CrossSaveRaceSettingsStore(<String, String>{
            SettingsService.keyGcjCorrectionEnabled: 'false',
            SettingsService.keyLookbackDays: '3',
          });
      final SettingsService settingsService = SettingsService(store: store);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsService: settingsService)),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(gcjCorrectionSwitch());
      await tester.tap(gcjCorrectionSwitch());
      await tester.pump();

      await tapVisibleText(tester, '保存');

      final Map<String, String> settingsAfterSave = await settingsService
          .loadSettings();
      expect(
        settingsAfterSave[SettingsService.keyGcjCorrectionEnabled],
        'true',
      );

      store.failFirstGcjWrite = true;
      store.firstGcjWriteCompleter!.complete();
      await tester.pumpAndSettle();

      final Switch rewriteSwitch = tester.widget<Switch>(gcjCorrectionSwitch());
      expect(rewriteSwitch.value, isTrue);

      final Map<String, String> settings = await settingsService.loadSettings();
      expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
    },
  );

  testWidgets(
    'failed rewrite switch persistence reverts switch and shows error',
    (WidgetTester tester) async {
      useLargeTestViewport(tester);

      final SettingsService settingsService = SettingsService(
        store: ThrowOnWriteSettingsStore(<String, String>{
          SettingsService.keyGcjCorrectionEnabled: 'false',
          SettingsService.keyLookbackDays: '3',
        }),
      );

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(settingsService: settingsService)),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(gcjCorrectionSwitch());
      await tester.tap(gcjCorrectionSwitch());
      await tester.pumpAndSettle();

      final Switch rewriteSwitch = tester.widget<Switch>(gcjCorrectionSwitch());
      expect(rewriteSwitch.value, isFalse);
      expect(find.text('设置保存失败: Exception: save failed'), findsOneWidget);
    },
  );

  testWidgets('Strava save flows preserve rewrite switch value', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyGcjCorrectionEnabled: 'true',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authorizeStrava: (String clientId, String clientSecret) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'Strava Client ID', '12345');
    await enterVisibleText(tester, 'Strava Client Secret', 'secret-xyz');

    await tapVisibleText(tester, '保存');

    Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');

    await tapVisibleText(tester, '授权 Strava');

    settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyGcjCorrectionEnabled], 'true');
  });

  testWidgets('Strava auth does not continue when general save is invalid', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    int authorizeCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          authorizeStrava: (String clientId, String clientSecret) async {
            authorizeCalls++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'Strava Client ID', '12345');
    await enterVisibleText(tester, 'Strava Client Secret', 'secret-xyz');
    await enterVisibleText(tester, '同步最近几天（默认 3）', '0');

    await tapVisibleText(tester, '授权 Strava');

    expect(authorizeCalls, 0);
    expect(find.text('请输入大于 0 的整数天数'), findsOneWidget);
    expect(find.text('Strava 授权成功'), findsNothing);
    expect(find.text('授权取消或失败'), findsNothing);
  });

  testWidgets('submitting lookback days field saves sync settings', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyLookbackDays: '3',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final Finder field = fieldWithLabel('同步最近几天（默认 3）');
    await tester.ensureVisible(field);
    await tester.enterText(field, '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('同步设置已保存'), findsOneWidget);

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '5');
  });

  testWidgets('invalid lookback days shows error and does not persist', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    FlutterSecureStorage.setMockInitialValues(<String, String>{
      SettingsService.keyLookbackDays: '3',
    });

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    await enterVisibleText(tester, '同步最近几天（默认 3）', '0');
    await tapVisibleText(tester, '保存同步设置');

    expect(find.text('请输入大于 0 的整数天数'), findsOneWidget);

    final Map<String, String> settings = await SettingsService().loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '3');
  });

  testWidgets('sync settings save failure shows error and keeps value', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final SettingsService settingsService = SettingsService(
      store: ThrowOnWriteSettingsStore(<String, String>{
        SettingsService.keyLookbackDays: '3',
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, '同步最近几天（默认 3）', '6');
    await tapVisibleText(tester, '保存同步设置');

    expect(find.text('设置保存失败: Exception: save failed'), findsOneWidget);
    expect(find.text('同步设置已保存'), findsNothing);

    final Map<String, String> settings = await settingsService.loadSettings();
    expect(settings[SettingsService.keyLookbackDays], '3');
  });

  testWidgets('successful OneLap save dismisses keyboard focus', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          validateOneLapLogin: (String username, String password) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterVisibleText(tester, 'OneLap 用户名', 'focus-user');
    await enterVisibleText(tester, 'OneLap 密码', 'focus-pass');

    final Finder passwordField = fieldWithLabel('OneLap 密码');
    await tester.tap(passwordField);
    await tester.pump();
    expect(hasFocusedEditableText(tester), isTrue);

    await tapVisibleText(tester, '保存 OneLap 账号');

    expect(hasFocusedEditableText(tester), isFalse);
  });

  testWidgets('saving sync settings dismisses keyboard focus', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    final Finder field = fieldWithLabel('同步最近几天（默认 3）');
    await tester.tap(field);
    await tester.pump();
    expect(hasFocusedEditableText(tester), isTrue);

    await tester.enterText(field, '6');
    await tapVisibleText(tester, '保存同步设置');

    expect(hasFocusedEditableText(tester), isFalse);
  });

  testWidgets('disposing settings screen during load does not throw', (
    WidgetTester tester,
  ) async {
    useLargeTestViewport(tester);

    final Completer<void> readCompleter = Completer<void>();
    final SettingsService settingsService = SettingsService(
      store: DelayedReadSettingsStore(readCompleter),
    );

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsService: settingsService)),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    readCompleter.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
