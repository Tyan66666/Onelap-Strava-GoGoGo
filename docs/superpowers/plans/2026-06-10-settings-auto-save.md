# Settings Auto-Save Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove redundant save buttons from the settings page and make upload platform toggles auto-save.

**Architecture:** Modify `settings_screen.dart` to auto-save upload toggles on change (following the existing GCJ pattern), remove the "保存上传设置" and bottom "保存" buttons, and inline Strava credential saving in `_authorizeStrava`.

**Tech Stack:** Flutter/Dart, `flutter_secure_storage` for persistence, `flutter_test` for testing.

---

## File Structure

Only one file is modified: `lib/screens/settings_screen.dart`
Test file: `test/screens/settings_screen_test.dart`

## Task 1: Add auto-save to upload toggles

**Files:**
- Modify: `lib/screens/settings_screen.dart:456-462` (toggle handlers)
- Modify: `lib/screens/settings_screen.dart:31-44` (state variables)

- [ ] **Step 1: Add state variables for upload toggle auto-save**

Add to `_SettingsScreenState` state variables (around line 43):
```dart
bool _savingUploadToStrava = false;
bool _savingUploadToXingzhe = false;
bool? _pendingUploadToStrava;
bool? _pendingUploadToXingzhe;
bool _confirmedUploadToStrava = true;
bool _confirmedUploadToXingzhe = false;
```

- [ ] **Step 2: Replace `_toggleUploadToStrava` with auto-save logic**

Replace the current `_toggleUploadToStrava` method (line 456-458) with:
```dart
Future<void> _toggleUploadToStrava(bool value) async {
  if (!value && !_uploadToXingzhe) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要选择一个上传平台')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置保存失败: $e')),
        );
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
```

- [ ] **Step 3: Replace `_toggleUploadToXingzhe` with auto-save logic**

Replace the current `_toggleUploadToXingzhe` method (line 460-462) with:
```dart
Future<void> _toggleUploadToXingzhe(bool value) async {
  if (!value && !_uploadToStrava) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要选择一个上传平台')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设置保存失败: $e')),
        );
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
```

- [ ] **Step 4: Run tests to verify existing tests still pass**

Run: `flutter test test/screens/settings_screen_test.dart`
Expected: Some tests will fail (expected — they reference removed buttons)

## Task 2: Remove redundant buttons and methods

**Files:**
- Modify: `lib/screens/settings_screen.dart`

- [ ] **Step 1: Remove `_saveUploadSettings` method**

Delete the `_saveUploadSettings` method (lines 421-454).

- [ ] **Step 2: Remove `_savingUploadSettings` state variable**

Delete `bool _savingUploadSettings = false;` (line 43).

- [ ] **Step 3: Remove "保存上传设置" button from build method**

Delete the ElevatedButton for "保存上传设置" (lines 727-743).

- [ ] **Step 4: Remove bottom "保存" button from build method**

Delete the bottom ElevatedButton for "保存" (line 885).

- [ ] **Step 5: Remove `_save` method**

Delete the `_save` method (lines 112-143).

- [ ] **Step 6: Update `_authorizeStrava` to inline save logic**

Replace the `_authorizeStrava` method's call to `_save()` (line 502) with inline save of Client ID and Client Secret only:
```dart
Future<void> _authorizeStrava() async {
  final clientId = _controllers[SettingsService.keyStravaClientId]!.text.trim();
  final clientSecret = _controllers[SettingsService.keyStravaClientSecret]!.text.trim();

  if (clientId.isEmpty || clientSecret.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Strava Client ID 和 Client Secret')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置保存失败: $e')),
      );
    }
    return;
  }

  final navigator = Navigator.of(context);

  final result = await (widget.authorizeStrava?.call(clientId, clientSecret) ??
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Strava 授权成功')),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('授权取消或失败')),
    );
  }
}
```

- [ ] **Step 7: Run analyze to check for issues**

Run: `flutter analyze`
Expected: No issues

## Task 3: Update tests

**Files:**
- Modify: `test/screens/settings_screen_test.dart`

- [ ] **Step 1: Delete test `general save rejects invalid lookback days`**

Delete lines 450-477.

- [ ] **Step 2: Delete test `general save failure shows error and no success state`**

Delete lines 479-500.

- [ ] **Step 3: Delete test `general save keeps confirmed rewrite state in sync during toggle race`**

Delete lines 658-698.

- [ ] **Step 4: Delete test `Strava save flows preserve rewrite switch value`**

Delete lines 727-757.

- [ ] **Step 5: Delete test `Strava auth does not continue when general save is invalid`**

Delete lines 759-788.

- [ ] **Step 6: Update test `preserves entered credentials after successful Strava auth`**

Update the test at line 200. The "授权 Strava" button now only saves Client ID and Client Secret, not OneLap credentials. Update expectations:
```dart
testWidgets('preserves entered Strava credentials after successful auth', (
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

  await enterVisibleText(tester, 'Client ID（客户端ID）', '12345');
  await enterVisibleText(tester, 'Client Secret（客户端密钥）', 'secret-xyz');

  await tapVisibleText(tester, '授权 Strava');

  final Map<String, String> settings = await SettingsService().loadSettings();
  expect(settings[SettingsService.keyStravaClientId], '12345');
  expect(settings[SettingsService.keyStravaClientSecret], 'secret-xyz');
});
```

- [ ] **Step 7: Add test `tapping upload to Strava toggle immediately persists setting`**

```dart
testWidgets('tapping upload to Strava toggle immediately persists setting', (
  WidgetTester tester,
) async {
  useLargeTestViewport(tester);

  final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
    SettingsService.keyUploadToStrava: 'true',
    SettingsService.keyUploadToXingzhe: 'false',
    SettingsService.keyLookbackDays: '3',
  });
  final SettingsService settingsService = SettingsService(store: store);

  await tester.pumpWidget(
    MaterialApp(home: SettingsScreen(settingsService: settingsService)),
  );
  await tester.pumpAndSettle();

  final Finder stravaSwitch = find.descendant(
    of: find.widgetWithText(SwitchListTile, '上传到 Strava'),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(stravaSwitch);
  await tester.tap(stravaSwitch);
  await tester.pumpAndSettle();

  final Map<String, String> settings = await settingsService.loadSettings();
  expect(settings[SettingsService.keyUploadToStrava], 'false');
});
```

- [ ] **Step 8: Add test `tapping upload to Xingzhe toggle immediately persists setting`**

```dart
testWidgets('tapping upload to Xingzhe toggle immediately persists setting', (
  WidgetTester tester,
) async {
  useLargeTestViewport(tester);

  final InMemorySettingsStore store = InMemorySettingsStore(<String, String>{
    SettingsService.keyUploadToStrava: 'true',
    SettingsService.keyUploadToXingzhe: 'false',
    SettingsService.keyLookbackDays: '3',
  });
  final SettingsService settingsService = SettingsService(store: store);

  await tester.pumpWidget(
    MaterialApp(home: SettingsScreen(settingsService: settingsService)),
  );
  await tester.pumpAndSettle();

  final Finder xingzheSwitch = find.descendant(
    of: find.widgetWithText(SwitchListTile, '上传到 行者'),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(xingzheSwitch);
  await tester.tap(xingzheSwitch);
  await tester.pumpAndSettle();

  final Map<String, String> settings = await settingsService.loadSettings();
  expect(settings[SettingsService.keyUploadToXingzhe], 'true');
});
```

- [ ] **Step 9: Add test `cannot turn off both upload platforms`**

```dart
testWidgets('cannot turn off both upload platforms', (
  WidgetTester tester,
) async {
  useLargeTestViewport(tester);

  FlutterSecureStorage.setMockInitialValues(<String, String>{
    SettingsService.keyUploadToStrava: 'true',
    SettingsService.keyUploadToXingzhe: 'true',
    SettingsService.keyLookbackDays: '3',
  });

  await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
  await tester.pumpAndSettle();

  final Finder xingzheSwitch = find.descendant(
    of: find.widgetWithText(SwitchListTile, '上传到 行者'),
    matching: find.byType(Switch),
  );
  await tester.ensureVisible(xingzheSwitch);
  await tester.tap(xingzheSwitch);
  await tester.pumpAndSettle();

  expect(find.text('至少需要选择一个上传平台'), findsOneWidget);

  final Map<String, String> settings = await SettingsService().loadSettings();
  expect(settings[SettingsService.keyUploadToXingzhe], 'true');
});
```

- [ ] **Step 10: Run all tests**

Run: `flutter test test/screens/settings_screen_test.dart`
Expected: All tests pass

## Task 4: Format and verify

- [ ] **Step 1: Format code**

Run: `dart format lib/screens/settings_screen.dart test/screens/settings_screen_test.dart`

- [ ] **Step 2: Run full verification**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings_screen.dart test/screens/settings_screen_test.dart docs/
git commit -m "feat: auto-save upload settings, remove redundant save buttons"
```
