# Fix Trainer Activity (.st) FIT Download Failure

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix OneLap trainer activities (骑行台) failing to sync because legacy durl download returns `.st` format instead of FIT, blocking the OTM fallback that correctly converts `.st` → `.fit`.

**Architecture:** After legacy URL download succeeds, validate the downloaded content is actual FIT (check magic bytes `.FIT` at offset 8-11). If not FIT, treat as failure so the existing OTM fallback (`fit_content/<base64path>`) kicks in. Also broaden the `canFallback` condition to handle expired signed URLs (403) and server errors (5xx) — all non-2xx on legacy URLs should fall through when an activity context is available.

**Tech Stack:** Dart, `dart:io` (File, RandomAccessFile), `dart:typed_data` (Uint8List), Dio

---

## Background

OneLap stores trainer activity data as `.st` files (proprietary format). The server converts `.st` → `.fit` on-the-fly ONLY when requested via:
```
GET /api/otm/ride_record/analysis/fit_content/<base64EncodedPath>
```

The app's download flow is three-tiered:

1. **RecordId download** → `fit_content/<recordId>` → returns **500** for `.st` activities
2. **Legacy direct download** → `durl` (signed URL to `.st` file) → returns **200** with `.st` content
3. **OTM fallback** → `fit_content/<base64path>` → returns **200** with valid FIT → **never reached**

The recordId endpoint returns 500 because the server can't convert `.st` to FIT given just a record ID.

The legacy `durl` (e.g., `https://fits.rfsvr.net/MATCH_xxx.st?e=...&token=...`) points to the raw `.st` file. When not expired, it returns 200 with `Content-Type: application/vnd.sailingtracker.track` and `.st` binary data. Since HTTP 200 means "success", the code marks `downloaded = true` and never reaches the OTM fallback. The `.st` data is saved as `.fit`, and `parseFitSessionMeta()` fails because `.st` is not valid FIT.

## File Structure

| File | Purpose | Change |
|------|---------|--------|
| `lib/services/onelap_client.dart:383-410` | `downloadFit()` legacy download loop | Add FIT validation after legacy download success |
| `lib/services/onelap_client.dart:390-397` | `canFallback` condition | Broaden to handle 403/5xx status codes |
| `lib/services/onelap_client.dart:548-618` | `_downloadViaOtmFallback()` and helpers | No changes — already handles MATCH identifiers |
| `lib/services/onelap_client.dart:678-714` | `_otmFitPath()` and `_isOtmMatchIdentifier()` | No changes — already correct |
| `test/services/onelap_client_test.dart` | Existing tests | **Must not modify** existing tests |
| `test/services/onelap_client_test.dart` | New tests | Add 3 new test cases |

---

### Task 1: Add `_isValidFitContent` helper method

**Files:**
- Create: (none)
- Modify: `lib/services/onelap_client.dart` — add new private method before `_downloadViaRecordId`

- [ ] **Step 1: Write the method**

Add after `_normalizeFitFilename` (around line 325), before `_selectDownloadUrl`:

```dart
Future<bool> _isValidFitContent(File file) async {
  try {
    final raf = await file.open(mode: FileMode.read);
    try {
      if (await raf.length() < 14) return false;
      await raf.setPosition(8);
      final Uint8List magic = Uint8List(4);
      await raf.readInto(magic);
      // FIT magic bytes at offset 8-11: ".FIT" = 0x2E 0x46 0x49 0x54
      return magic[0] == 0x2E &&
          magic[1] == 0x46 &&
          magic[2] == 0x49 &&
          magic[3] == 0x54;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}
```

This method reads bytes 8-11 from the downloaded file and checks for the FIT magic string ".FIT". Returns false for any error (file too small, read error, etc.) to ensure graceful fallback.

- [ ] **Step 2: Run existing tests**

Run: `flutter test test/services/onelap_client_test.dart`
Expected: All existing tests PASS — new method not yet called, no regressions.

- [ ] **Step 3: Commit**

```bash
git add lib/services/onelap_client.dart
git commit -m "Add _isValidFitContent helper to validate FIT magic bytes"
```

---

### Task 2: Validate FIT content after legacy download success

**Files:**
- Modify: `lib/services/onelap_client.dart:383-403` — legacy download loop

- [ ] **Step 1: Modify the legacy download loop**

In `downloadFit()`, replace lines 386-390:

```dart
// Before (lines 386-390):
          try {
            await _dio.download(downloadUrl, tempPath.path);
            lastError = null;
            downloaded = true;
            break;
```

Replace with:

```dart
          try {
            await _dio.download(downloadUrl, tempPath.path);
            lastError = null;
            if (await _isValidFitContent(tempPath)) {
              downloaded = true;
              break;
            }
            // Downloaded data is not valid FIT (e.g., .st format from trainer
            // activities). Remove temp file and continue to next URL or
            // OTM fallback.
            if (await tempPath.exists()) {
              await tempPath.delete().catchError((_) => tempPath);
            }
            // Fall through: continue to next URL, or to OTM fallback if last URL.
          } on DioException catch (e) {
```

This ensures that:
- Valid FIT data → break and proceed to dedup (original behavior preserved)
- Non-FIT data (like `.st`) → delete temp, don't set `downloaded`, continue loop
- The loop naturally falls through to OTM fallback when all legacy URLs fail or return non-FIT

- [ ] **Step 2: Run existing tests**

Run: `flutter test test/services/onelap_client_test.dart`
Expected: Some existing tests might FAIL because they mock downloads that return non-FIT bytes (e.g., `[9, 8, 7]` or `[1, 2, 3]`). These will need to be updated to return valid FIT magic bytes.

- [ ] **Step 3: Update affected existing tests**

The following tests use mock download responses with arbitrary bytes that are not valid FIT. Each must be updated so the mock returns valid FIT bytes (including `.FIT` at offset 8-11):

**Test: `falls back from absolute durl to raw fit_url after 404`** (line 1893)
- Line 1901: Change `bytes: <int>[9, 8, 7]` → valid FIT bytes (see helper below)
- The first URL (durl) returns 404, so it falls through naturally → the second URL must return valid FIT

**Test: `falls back to raw fileKey path after durl and raw fit urls 404`** (line 1958)
- Line 1980: Change `bytes: <int>[1, 2, 3]` → valid FIT bytes

**Test: `falls back to OTM fit content download after standard URLs fail`** (line 2096)
- Line 2146: Change `bytes: <int>[4, 5, 6, 7]` → valid FIT bytes (OTM fallback response)

**Test: `falls back to OTM fit content download for MATCH identifiers after standard URLs fail`** (line 4415)
- Line 4464: Change `bytes: <int>[7, 6, 5, 4]` → valid FIT bytes (OTM fallback response)

**Test: `downloads FIT through the recordId OTM endpoint before trying legacy URLs`** (line 2196)
- Line 2232: Change `bytes: <int>[7, 7, 7]` → valid FIT bytes (recordId response)

**Test: `falls back to u.onelap.cn recordId FIT endpoint after otm.onelap.cn returns 500`** (line 2299)
- Line 2346: Change `bytes: <int>[6, 9, 1]` → valid FIT bytes (fallback host response)

Use this helper to create valid FIT byte arrays in tests:

```dart
List<int> _validFitBytes(List<int> payload) {
  // FIT header: 14-byte header + ".FIT" at offset 8 + payload
  final header = <int>[0x0E, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2E, 0x46, 0x49, 0x54, 0x00, 0x00];
  return [...header, ...payload];
}
```

Add this helper near the top of `main()` in the test file, and replace payload bytes like `[9, 8, 7]` with `_validFitBytes([9, 8, 7])`.

**IMPORTANT**: Only change existing tests where the bytes ARE the final downloaded payload. Do NOT change:
- `bytes: <int>[]` (empty body responses)
- 404/500 error responses
- Any response that is NOT the final successful download

- [ ] **Step 4: Run tests after updates**

Run: `flutter test test/services/onelap_client_test.dart`
Expected: All existing tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/services/onelap_client.dart test/services/onelap_client_test.dart
git commit -m "Validate FIT content after legacy download to detect .st files"
```

---

### Task 3: Broaden `canFallback` condition for legacy URL errors

**Files:**
- Modify: `lib/services/onelap_client.dart:393-396` — `canFallback` condition

- [ ] **Step 1: Broaden the condition**

In `downloadFit()`, change lines 393-396:

```dart
// Before:
            final bool canFallback =
                statusCode == 404 &&
                (i < downloadUrls.length - 1 || activity != null);

// After:
            final bool canFallback =
                statusCode != null &&
                statusCode != 200 &&
                (i < downloadUrls.length - 1 || activity != null);
```

**Rationale**: Any non-200 status from a legacy URL should allow fall-through to the next URL or to the OTM fallback. This covers:
- `404`: file moved/deleted (already handled)
- `403`: expired signed URL token (new)
- `410`: file gone permanently (new)
- `5xx`: CDN server error (new)

When `activity != null`, even the last URL failing with non-200 will fall through to the OTM fallback. When `activity` is null, the last URL failing throws as expected (no fallback available).

- [ ] **Step 2: Run existing tests**

Run: `flutter test test/services/onelap_client_test.dart`
Expected: All existing tests PASS

- [ ] **Step 3: Commit**

```bash
git add lib/services/onelap_client.dart
git commit -m "Broaden canFallback to handle expired durl and server errors"
```

---

### Task 4: Write new test for .st → FIT fallback scenario

**Files:**
- Modify: `test/services/onelap_client_test.dart` — add new test after existing MATCH tests

- [ ] **Step 1: Write the test**

Add after line 4584 (after `does not treat malformed MATCH identifiers` test):

```dart
    test(
      'falls back to OTM fit content when durl returns non-FIT .st content',
      () async {
        final List<String> requests = <String>[];
        const String matchIdentifier =
            'MATCH_677767-2026-03-05-21-06-35-log.st';
        final String otmFitContentUrl =
            'https://otm.onelap.cn/api/otm/ride_record/analysis/fit_content/'
            '${base64.encode(utf8.encode(matchIdentifier))}';
        const String recordId = '69a984cab29588524341fe6b';
        const String recordIdFitContentUrl =
            'https://otm.onelap.cn/api/otm/ride_record/analysis/fit_content/$recordId';

        final Dio dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          final String url = options.uri.toString();
          requests.add(url);

          // Login
          if (url == 'http://example.com/api/login') {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 200,
                'data': [
                  {
                    'token': 'otm-token-123',
                    'refresh_token': 'otm-refresh-456',
                  },
                ],
              }),
              200,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/json'],
              },
            );
          }

          // recordId download returns 500 (server can't convert .st → .fit)
          if (url == recordIdFitContentUrl) {
            return ResponseBody.fromBytes(
              <int>[],
              HttpStatus.internalServerError,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/octet-stream'],
              },
            );
          }

          // durl returns 200 with .st content (NOT valid FIT)
          if (url == 'http://fits.rfsvr.net/demo.st?token=abc') {
            return ResponseBody.fromBytes(
              <int>[0x01, 0x0C, 0x08, 0x01, 0x10], // .st header, not .FIT
              HttpStatus.ok,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>[
                  'application/vnd.sailingtracker.track',
                ],
              },
            );
          }

          // Other legacy URLs 404
          if (url == 'http://example.com/MATCH_677767-2026-03-05-21-06-29-log.st') {
            return ResponseBody.fromBytes(
              <int>[],
              HttpStatus.notFound,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/octet-stream'],
              },
            );
          }

          // OTM fallback returns valid FIT
          if (url == otmFitContentUrl) {
            return ResponseBody.fromBytes(
              _validFitBytes(<int>[8, 8, 8]),
              HttpStatus.ok,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/octet-stream'],
              },
            );
          }

          return ResponseBody.fromString('not found', 404);
        });
        final Directory outputDir = await Directory.systemTemp.createTemp(
          'onelap-client-st-fallback-',
        );

        addTearDown(() async {
          if (await outputDir.exists()) {
            await outputDir.delete(recursive: true);
          }
        });

        final OneLapClient client = OneLapClient(
          baseUrl: 'http://example.com',
          username: 'unused',
          password: 'unused',
          dio: dio,
        );

        final File downloaded = await client.downloadFit(
          'http://fits.rfsvr.net/demo.st?token=abc',
          'demo.fit',
          outputDir,
          activity: const OneLapActivity(
            activityId: '677767',
            recordId: recordId,
            startTime: '2026-03-05T21:06:35',
            fitUrl: 'http://fits.rfsvr.net/demo.st?token=abc',
            recordKey: 'fitUrl:MATCH_677767-2026-03-05-21-06-35-log.st',
            sourceFilename: 'demo.fit',
            rawFitUrlAlt: matchIdentifier,
            rawDurl: 'http://fits.rfsvr.net/demo.st?token=abc',
          ),
        );

        // Verify OTM fallback URL was called
        expect(requests, contains(otmFitContentUrl));
        // Verify valid FIT content was downloaded
        expect(
          await downloaded.readAsBytes(),
          _validFitBytes(<int>[8, 8, 8]),
        );
      },
    );
```

- [ ] **Step 2: Run the new test**

Run: `flutter test --plain-name "falls back to OTM fit content when durl returns non-FIT .st content"`
Expected: PASS — new test verifies the fix works

- [ ] **Step 3: Write companion test — durl with 403 falls through**

Add after the new test:

```dart
    test(
      'falls back to OTM fit content when durl returns 403',
      () async {
        final List<String> requests = <String>[];
        const String matchIdentifier =
            'MATCH_677767-2026-03-05-21-06-35-log.st';
        final String otmFitContentUrl =
            'https://otm.onelap.cn/api/otm/ride_record/analysis/fit_content/'
            '${base64.encode(utf8.encode(matchIdentifier))}';

        final Dio dio = Dio();
        dio.httpClientAdapter = _FakeHttpClientAdapter((options) async {
          final String url = options.uri.toString();
          requests.add(url);

          if (url == 'http://example.com/api/login') {
            return ResponseBody.fromString(
              jsonEncode({
                'code': 200,
                'data': [
                  {
                    'token': 'otm-token-123',
                    'refresh_token': 'otm-refresh-456',
                  },
                ],
              }),
              200,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/json'],
              },
            );
          }

          // Expired signed durl returns 403
          if (url == 'http://fits.rfsvr.net/demo.st?token=expired') {
            return ResponseBody.fromBytes(
              <int>[],
              HttpStatus.forbidden,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['text/plain'],
              },
            );
          }

          // Other legacy URLs 404
          if (url == 'http://example.com/MATCH_677767-2026-03-05-21-06-29-log.st') {
            return ResponseBody.fromBytes(
              <int>[],
              HttpStatus.notFound,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/octet-stream'],
              },
            );
          }

          // OTM fallback returns valid FIT
          if (url == otmFitContentUrl) {
            return ResponseBody.fromBytes(
              _validFitBytes(<int>[9, 9, 9]),
              HttpStatus.ok,
              headers: <String, List<String>>{
                Headers.contentTypeHeader: <String>['application/octet-stream'],
              },
            );
          }

          return ResponseBody.fromString('not found', 404);
        });
        final Directory outputDir = await Directory.systemTemp.createTemp(
          'onelap-client-403-fallback-',
        );

        addTearDown(() async {
          if (await outputDir.exists()) {
            await outputDir.delete(recursive: true);
          }
        });

        final OneLapClient client = OneLapClient(
          baseUrl: 'http://example.com',
          username: 'unused',
          password: 'unused',
          dio: dio,
        );

        final File downloaded = await client.downloadFit(
          'http://fits.rfsvr.net/demo.st?token=expired',
          'demo.fit',
          outputDir,
          activity: const OneLapActivity(
            activityId: '677767',
            startTime: '2026-03-05T21:06:35',
            fitUrl: 'http://fits.rfsvr.net/demo.st?token=expired',
            recordKey: 'fitUrl:MATCH_677767-2026-03-05-21-06-35-log.st',
            sourceFilename: 'demo.fit',
            rawFitUrlAlt: matchIdentifier,
            rawDurl: 'http://fits.rfsvr.net/demo.st?token=expired',
          ),
        );

        expect(requests, contains(otmFitContentUrl));
        expect(
          await downloaded.readAsBytes(),
          _validFitBytes(<int>[9, 9, 9]),
        );
      },
    );
```

- [ ] **Step 4: Run both new tests**

Run: `flutter test --plain-name "falls back to OTM fit content when durl"`
Expected: Both new tests PASS

- [ ] **Step 5: Commit**

```bash
git add test/services/onelap_client_test.dart
git commit -m "Add tests for .st → FIT fallback and 403 durl handling"
```

---

### Task 5: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run full test suite**

```bash
flutter test
```

Expected: ALL tests PASS, no regressions.

- [ ] **Step 2: Run dart format check**

```bash
dart format --output=none --set-exit-if-changed lib test
```

Expected: Exit 0, no formatting issues.

- [ ] **Step 3: Run flutter analyze**

```bash
flutter analyze
```

Expected: No issues found.

- [ ] **Step 4: Commit (if any format/analyze fixes needed)**

```bash
git add -A
git commit -m "Format and analyze fixes"
```

---

## Summary of Changes

| Change | File | Lines |
|--------|------|-------|
| New `_isValidFitContent()` method | `lib/services/onelap_client.dart` | +20 (after line 325) |
| FIT validation after legacy download | `lib/services/onelap_client.dart:386-390` | ~8 lines modified |
| Broaden `canFallback` to non-200 | `lib/services/onelap_client.dart:394-396` | ~3 lines modified |
| Existing tests: replace raw bytes with valid FIT | `test/services/onelap_client_test.dart` | ~6 locations |
| New test: `.st` → FIT fallback | `test/services/onelap_client_test.dart` | +100 lines |
| New test: 403 durl → fallback | `test/services/onelap_client_test.dart` | +95 lines |

## Key Design Decisions

1. **FIT validation uses magic bytes only** — does not attempt full FIT parsing. `fit_tool` parsing would be too slow for a validation step and would create a circular dependency risk (the validation is in the download layer, parsing is in the sync layer).

2. **Validation only after legacy download, not after recordId or OTM** — the recordId and OTM endpoints are known to return valid FIT (they're server-side conversion endpoints). Only legacy direct downloads (durls) have the `.st` vs `.fit` ambiguity.

3. **`canFallback` uses `statusCode != 200` instead of listing specific codes** — this is forward-compatible with any CDN error response. 2xx (201, 204, 206) are unlikely for file downloads but theoretically could occur; if they do, they'd also fail FIT validation and fall through.

4. **Original download logic preserved** — the three-tier fallback chain (recordId → legacy → OTM) is untouched. Only the success condition in tier 2 is tightened.
