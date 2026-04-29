# PR #4 Review Fixups Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three PR #4 review blockers on a separate branch by restoring declared dependencies, removing sensitive Xingzhe logs/errors, and preventing empty-fingerprint sync history collisions.

**Architecture:** Keep the patch minimal and local to existing files. Add a focused regression test for the history identity bug first, then make the smallest production changes in `state_store.dart`, `xingzhe_client.dart`, and `pubspec.yaml`, followed by analyzer and test verification.

**Tech Stack:** Flutter, Dart, flutter_test, Dio, flutter_secure_storage

---

### Task 1: Add a regression test for empty-fingerprint history records

**Files:**
- Create: `test/services/state_store_test.dart`
- Modify: `lib/services/state_store.dart`

- [ ] **Step 1: Reuse the existing `path_provider` test stub pattern from another service test**

Read `test/services/sync_engine_test.dart` and copy its `path_provider` method-channel stubbing approach so `StateStore` tests can use an isolated temp documents directory.

- [ ] **Step 2: Write the failing test**

Add a test that saves two `SyncRecord` entries with:
- empty `fingerprint`
- different `sourceFilename` and/or `startTime`
- failed platform results

Then load them back with `loadSyncRecords()` and assert that both records are still present.

Example assertion shape:

```dart
expect(records, hasLength(2));
expect(records.map((r) => r.sourceFilename), containsAll(<String>[
  'first.fit',
  'second.fit',
]));
```

- [ ] **Step 3: Run the new test to verify it fails**

Run: `flutter test test/services/state_store_test.dart`

Expected: the new test fails because one empty-fingerprint record overwrites or merges into the other.

- [ ] **Step 4: Implement the minimal history identity fix**

In `lib/services/state_store.dart`, add one shared private helper that returns the record identity:

```dart
String _historyIdentity(SyncRecord record) {
  if (record.fingerprint.isNotEmpty) {
    return 'fp:${record.fingerprint}';
  }
  return 'fallback:${record.startTime}:${record.sourceFilename}';
}
```

Use that helper in both:
- `saveSyncRecords()` replacement lookup
- `loadSyncRecords()` merge map key

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `flutter test test/services/state_store_test.dart`

Expected: PASS

### Task 2: Restore declared dependencies for the Xingzhe client

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

- [ ] **Step 1: Verify the current missing-package failure**

Run: `flutter analyze`

Expected: unresolved import/package errors for `encrypt`, `http_parser`, and `pointycastle` from `lib/services/xingzhe_client.dart`.

- [ ] **Step 2: Add the missing package declarations**

Add these dependencies under `dependencies` in `pubspec.yaml`:

```yaml
  encrypt: ^5.0.3
  http_parser: ^4.0.2
  pointycastle: ^3.9.1
```

Keep the existing dependency ordering/style consistent with the file.

- [ ] **Step 3: Refresh dependencies**

Run: `flutter pub get`

Expected: dependency resolution completes successfully.

### Task 3: Remove sensitive Xingzhe logging and raw secret exposure

**Files:**
- Create: `test/services/xingzhe_client_test.dart`
- Modify: `lib/services/xingzhe_client.dart`

- [ ] **Step 1: Write the failing sanitization test**

Add a focused test that triggers a Xingzhe login or upload failure with a fake Dio response containing secret-like values in the body, then assert the thrown error string does not contain those raw values.

Example assertion shape:

```dart
expect('$error', isNot(contains('sessionid=')));
expect('$error', isNot(contains('super-secret')));
expect('$error', contains('HTTP 401'));
```

- [ ] **Step 2: Run the sanitization test to verify it fails**

Run: `flutter test test/services/xingzhe_client_test.dart`

Expected: FAIL because the current error string includes raw response-derived content.

- [ ] **Step 3: Apply the minimal sanitization change**

Make these changes only:
- remove logs that print usernames, cookies, session IDs, encrypted passwords, raw request/response bodies, and file-path/session details not needed for operation
- keep either no logs or only coarse non-sensitive progress logs if necessary
- ensure thrown errors do not include any response-derived secret content, including interpolations from `response.data`, `payload['message']`, `payload['msg']`, `$payload`, or `$e` where those values may contain secrets

Use fixed summaries such as:

```dart
throw XingzhePermanentError('行者登录失败: HTTP ${e.response?.statusCode ?? 0}');
throw XingzhePermanentError('行者上传失败: HTTP $status');
```

- [ ] **Step 4: Run the Xingzhe sanitization test to verify it passes**

Run: `flutter test test/services/xingzhe_client_test.dart`

Expected: PASS

- [ ] **Step 5: Read the diff to confirm scope stayed minimal**

Run: `git diff -- lib/services/xingzhe_client.dart test/services/xingzhe_client_test.dart pubspec.yaml pubspec.lock`

Check that only sensitive-output handling changed and no unrelated logic was rewritten.

### Task 4: Run project verification

**Files:**
- Verify only: repository root files already changed above

- [ ] **Step 1: Format changed code**

Run: `dart format lib/services/state_store.dart lib/services/xingzhe_client.dart test/services/state_store_test.dart test/services/xingzhe_client_test.dart`

Expected: formatting completes without errors.

- [ ] **Step 2: Run analyzer**

Run: `flutter analyze`

Expected: no missing-package or Xingzhe compile errors remain.

- [ ] **Step 3: Run full tests**

Run: `flutter test`

Expected: all tests pass.
