# Dark Mode + Sync Performance Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add system-following dark mode and increase FIT download concurrency for faster syncs.

**Architecture:** Dark mode uses Flutter's built-in `ThemeMode.system` with a `darkTheme` generated from the same seed color. Download concurrency bump is a single constant change in `SyncEngine`.

**Tech Stack:** Flutter, Material 3, `ColorScheme.fromSeed`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `lib/main.dart:48-51` | Modify | Add `darkTheme` + `themeMode` to `MaterialApp` |
| `lib/services/sync_engine.dart:69` | Modify | Increase `downloadConcurrency` default from 2 to 3 |

---

### Task 1: Add System Dark Mode

**Files:**
- Modify: `lib/main.dart:44-54`
- Test: `flutter test test/widget_test.dart` (smoke test still passes)

- [ ] **Step 1: Run existing tests to establish baseline**

Run: `flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 2: Add darkTheme and themeMode to MaterialApp**

Edit `lib/main.dart:48-51`, change:

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
  useMaterial3: true,
),
```

To:

```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
  useMaterial3: true,
),
darkTheme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepOrange,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
),
themeMode: ThemeMode.system,
```

- [ ] **Step 3: Verify the app builds**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 4: Run tests**

Run: `flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: add system-following dark mode"
```

---

### Task 2: Increase Download Concurrency

**Files:**
- Modify: `lib/services/sync_engine.dart:69`
- Modify: `test/services/sync_engine_test.dart:580-627`

- [ ] **Step 1: Update default downloadConcurrency**

Edit `lib/services/sync_engine.dart:69`, change:

```dart
this.downloadConcurrency = 2,
```

To:

```dart
this.downloadConcurrency = 3,
```

- [ ] **Step 2: Update test to reflect new default**

The existing test at `test/services/sync_engine_test.dart:610` explicitly passes `downloadConcurrency: 2`, so it will still pass. No change needed to the test — the test verifies the *mechanism*, not the default value.

- [ ] **Step 3: Run tests**

Run: `flutter test test/services/sync_engine_test.dart`
Expected: PASS

- [ ] **Step 4: Run full verification**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/sync_engine.dart
git commit -m "perf: increase download concurrency from 2 to 3"
```
