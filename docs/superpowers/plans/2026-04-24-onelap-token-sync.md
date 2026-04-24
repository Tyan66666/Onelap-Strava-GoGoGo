# OneLap Token Sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore OneLap sync by replacing the legacy session-based activity fetch with the modern token-backed record list, detail, and FIT download flow while keeping the current username/password settings UX.

**Architecture:** Keep all OneLap protocol changes inside `OneLapClient` plus one additive model field on `OneLapActivity`. Implement token bootstrap, token refresh, first-page record listing, per-record detail enrichment for backward-compatible dedupe keys, and record-ID-based FIT downloads, with focused regression coverage driving each behavior.

**Tech Stack:** Flutter, Dart, Dio, existing `flutter test` unit test suite

---

## File Map

### Modified files

- `lib/models/onelap_activity.dart`
  - Add one optional `recordId` field.
  - Preserve existing constructor shape and legacy fields.
- `lib/services/onelap_client.dart`
  - Replace legacy `/analysis/list` flow with token-backed OneLap OTM APIs.
  - Cache auth state in-memory.
  - Add token refresh and re-login retry logic.
  - Add detail enrichment for dedupe-compatible `recordKey` recovery.
  - Prefer record-ID FIT downloads before legacy direct URL fallbacks.
- `test/services/onelap_client_test.dart`
  - Replace legacy list tests with new token/list/detail regressions.
  - Add auth refresh and re-login recovery tests.
  - Add new record-ID download tests and explicit error-contract tests.

### Unchanged by design

- `lib/services/sync_engine.dart`
  - No sync orchestration changes.
- `lib/services/dedupe_service.dart`
  - Fingerprint format stays unchanged.
- `lib/services/state_store.dart`
  - No migration in this fix; compatibility is handled by `recordKey` recovery.
- `lib/screens/settings_screen.dart`
  - No UI changes. Existing `login()` validation path remains the only caller.

## Task 1: Add the additive model field first

**Files:**
- Modify: `lib/models/onelap_activity.dart`
- Test: `test/services/onelap_client_test.dart`

- [ ] **Step 1: Write the failing model-construction test**

Add a small test near other `OneLapClient` fixtures that constructs a
`OneLapActivity` with `recordId: '123'` and asserts the field is readable while
legacy fields remain intact.

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "stores recordId on OneLapActivity without affecting legacy fields"`

Expected: FAIL because `OneLapActivity` does not yet expose `recordId`.

- [ ] **Step 3: Add the minimal model field**

Update `lib/models/onelap_activity.dart` to:

- add `final String? recordId;`
- add `this.recordId,` to the constructor
- keep all existing required fields and field ordering stable unless formatter changes wrapping

- [ ] **Step 4: Re-run the focused model test**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "stores recordId on OneLapActivity without affecting legacy fields"`

Expected: PASS.

## Task 2: Drive token bootstrap through `login()`

**Files:**
- Modify: `test/services/onelap_client_test.dart`
- Modify: `lib/services/onelap_client.dart`

- [ ] **Step 1: Write the failing login success regression**

Add a test that:

- fakes `POST http://example.com/api/login`
- returns `{"code":200,"data":[{"token":"token-1","refresh_token":"refresh-1"}]}`
- calls `client.login()`
- then calls `listFitActivities()` with a fixture that forces the client onto
  the authenticated OTM record-list path
- asserts the follow-up request includes `Authorization: token-1`

- [ ] **Step 2: Run the focused login success test to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "login caches token and refresh token for subsequent authenticated requests"`

Expected: FAIL because `login()` currently validates only and does not cache auth.

- [ ] **Step 3: Write the failing missing-token regression**

Add a separate compatibility regression that fakes:

```json
{"code":0,"data":[{"token":"token-0","refresh_token":"refresh-0"}]}
```

and asserts `client.login()` still succeeds.

- [ ] **Step 4: Run the code-0 compatibility regression to verify it fails or is unproven**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "login still accepts OneLap success code 0 when token fields are present"`

Expected: FAIL or remain unimplemented until the new login parser is added.

- [ ] **Step 5: Write the failing missing-token regression**

Add a test that fakes a successful login status with missing auth fields, such as:

```json
{"code":200,"data":[{}]}
```

Assert `client.login()` throws a clear exception mentioning the missing token or
missing refresh token.

- [ ] **Step 6: Run the missing-token regression to verify it fails correctly**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "login fails when OneLap response omits required token fields"`

Expected: FAIL for the expected reason.

- [ ] **Step 7: Implement the minimal login/auth state change**

Update `lib/services/onelap_client.dart` to:

- add private in-memory fields for access token and refresh token
- parse `payload['data']` from `/api/login`
- continue accepting success code `0` as well as `200`
- require non-empty `token` and `refresh_token`
- cache both fields on success
- keep the existing error message style for non-success login codes

- [ ] **Step 8: Re-run the focused login tests**

Run:

- `flutter test test/services/onelap_client_test.dart --plain-name "login caches token and refresh token for subsequent authenticated requests"`
- `flutter test test/services/onelap_client_test.dart --plain-name "login still accepts OneLap success code 0 when token fields are present"`
- `flutter test test/services/onelap_client_test.dart --plain-name "login fails when OneLap response omits required token fields"`

Expected: PASS.

## Task 3: Build the shared authenticated OTM request helper

**Files:**
- Modify: `test/services/onelap_client_test.dart`
- Modify: `lib/services/onelap_client.dart`

- [ ] **Step 1: Write the failing refresh-success regression**

Add a test that:

- starts with cached `token-1` / `refresh-1`
- makes an authenticated request return HTTP `403`
- fakes `POST /api/token` with body `{"token":"refresh-1","from":"web","to":"web"}`
- returns refreshed auth:

```json
{"code":200,"data":{"token":"token-2","refresh_token":"refresh-2"}}
```

- retries the original request successfully
- asserts the retried request uses `Authorization: token-2`

- [ ] **Step 2: Run the refresh-success regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "refreshes OneLap auth token after a 403 response and retries once"`

Expected: FAIL because token refresh is not implemented.

- [ ] **Step 3: Write the failing refresh-without-new-refresh-token regression**

Add a test that:

- starts with cached `token-1` / `refresh-1`
- makes the authenticated request return `403`
- makes `POST /api/token` return:

```json
{"code":200,"data":{"token":"token-2"}}
```

- retries the original request successfully
- later triggers another `403`-driven refresh attempt
- asserts the cached refresh token remains `refresh-1` instead of being cleared

- [ ] **Step 4: Run the refresh-token-retention regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "retains the previous refresh token when OneLap refresh does not return a new one"`

Expected: FAIL because refresh handling is not implemented.

- [ ] **Step 5: Write the failing re-login fallback regression**

Add a test that:

- starts with cached `token-1` / `refresh-1`
- makes the authenticated request return `403`
- makes `POST /api/token` fail or return invalid auth data
- makes a fresh `POST /api/login` succeed with `token-3` / `refresh-3`
- retries the original request successfully
- asserts exactly one re-login retry path is used

- [ ] **Step 6: Run the re-login regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "re-logs in once when token refresh cannot recover an authenticated request"`

Expected: FAIL because re-login fallback is not implemented.

- [ ] **Step 7: Implement the minimal auth recovery helper**

Update `lib/services/onelap_client.dart` to:

- add a small authenticated request helper for new OTM APIs
- detect auth failures only on HTTP `401` or `403`
- refresh once through `POST /api/token`
- require top-level `code == 200` and non-empty refreshed `token`
- replace the cached refresh token only when the refresh response includes a new non-empty `refresh_token`
- if refresh fails, perform one fresh login and retry once
- avoid unbounded retry loops

- [ ] **Step 8: Re-run the auth recovery regressions**

Run:

- `flutter test test/services/onelap_client_test.dart --plain-name "refreshes OneLap auth token after a 403 response and retries once"`
- `flutter test test/services/onelap_client_test.dart --plain-name "retains the previous refresh token when OneLap refresh does not return a new one"`
- `flutter test test/services/onelap_client_test.dart --plain-name "re-logs in once when token refresh cannot recover an authenticated request"`

Expected: PASS.

## Task 4: Replace legacy activity listing with token-backed list and detail enrichment

**Files:**
- Modify: `test/services/onelap_client_test.dart`
- Modify: `lib/services/onelap_client.dart`

- [ ] **Step 1: Write the failing record-list regression**

Add a test that:

- fakes login returning token data
- fakes `POST http://example.com/api/otm/ride_record/list`
- asserts the request body is `{"page":1,"limit":50}`
- returns:

```json
{
  "code": 200,
  "data": {
    "list": [
      {
        "id": 77,
        "start_riding_time": "2026-04-24 08:00:00",
        "name": "Morning Ride"
      }
    ],
    "pagination": {"total": 1}
  }
}
```

- fakes `GET http://example.com/api/otm/ride_record/analysis/77`
- returns detail payload with `fileKey`, for example:

```json
{
  "code": 200,
  "data": {
    "fileKey": "geo/20260424/morning.fit"
  }
}
```

- calls `listFitActivities(since: DateTime.utc(2026, 4, 23))`
- asserts the returned activity has:
  - `activityId == '77'`
  - `recordId == '77'`
  - `recordKey == 'fileKey:geo/20260424/morning.fit'`
  - `sourceFilename == 'Morning Ride.fit'` or the exact normalized filename chosen by implementation

- [ ] **Step 2: Run the focused record-list regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "lists recent activities from the token-backed OTM record API and enriches recordKey from detail"`

Expected: FAIL because the client still calls legacy `/analysis/list`.

- [ ] **Step 3: Write the failing detail-fallback regression**

Add a second test that:

- fakes the same list response
- makes `GET /api/otm/ride_record/analysis/{id}` return a non-auth HTTP failure such as `404`
- asserts the activity is still returned
- asserts `recordKey == 'recordId:77'`
- asserts `recordId == '77'`

- [ ] **Step 4: Run the detail-fallback regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back to recordId-based recordKey when detail enrichment request fails"`

Expected: FAIL because legacy code does not have this path.

- [ ] **Step 5: Write the failing valid-detail-without-legacy-keys regression**

Add a test that:

- fakes list success
- fakes detail HTTP `200` with a valid payload such as `{"code":200,"data":{"name":"detail only"}}`
- asserts the activity is still returned
- asserts `recordKey == 'recordId:77'`

- [ ] **Step 6: Run the no-legacy-key regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back to recordId-based recordKey when detail payload has no legacy identity fields"`

Expected: FAIL because the path is not implemented.

- [ ] **Step 7: Write the failing invalid-detail-payload regression**

Add a test that:

- fakes list success
- fakes detail HTTP `200` with malformed payload such as `{"code":200,"data":[]}`
- asserts `listFitActivities(...)` throws a clear invalid-detail exception

- [ ] **Step 8: Run the invalid-detail regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when OneLap detail payload is invalid"`

Expected: FAIL for the expected reason.

- [ ] **Step 7: Implement the minimal token-backed list/detail flow**
- [ ] **Step 9: Implement the minimal token-backed list/detail flow**

Update `lib/services/onelap_client.dart` to:

- replace `_fetchActivitiesPayload()` with a token-backed `POST /api/otm/ride_record/list`
- parse success from top-level `code == 200` and nested `data.list`
- request only page 1, limit 50
- add a small detail fetch helper for `GET /api/otm/ride_record/analysis/{id}`
- recover legacy identity fields in priority order: `fileKey`, `fit_url`, `fitUrl`, `durl`
- set `recordKey` from recovered detail fields when available
- fall back to `recordId:<id>` when detail succeeds but has no legacy identity fields
- fall back to `recordId:<id>` when detail transport/HTTP fails non-auth
- throw a clear exception when detail HTTP succeeds but payload shape is invalid
- preserve `since` filtering and `limit` cutoff behavior

- [ ] **Step 10: Re-run the focused record-list/detail tests**

Run:

- `flutter test test/services/onelap_client_test.dart --plain-name "lists recent activities from the token-backed OTM record API and enriches recordKey from detail"`
- `flutter test test/services/onelap_client_test.dart --plain-name "falls back to recordId-based recordKey when detail enrichment request fails"`
- `flutter test test/services/onelap_client_test.dart --plain-name "falls back to recordId-based recordKey when detail payload has no legacy identity fields"`
- `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when OneLap detail payload is invalid"`

Expected: PASS.

## Task 5: Make record-ID FIT download the primary path

**Files:**
- Modify: `test/services/onelap_client_test.dart`
- Modify: `lib/services/onelap_client.dart`

- [ ] **Step 1: Write the failing record-ID FIT download regression**

Add a test that:

- constructs an activity with `recordId: '77'`
- fakes authenticated `GET https://otm.onelap.cn/api/otm/ride_record/analysis/fit_content/77`
- returns non-empty bytes
- calls `downloadFit(...)`
- asserts the new record-ID endpoint is requested before any legacy direct URL
  request
- asserts the written file bytes match the response body

- [ ] **Step 2: Run the record-ID FIT regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "downloads FIT through the recordId OTM endpoint before trying legacy URLs"`

Expected: FAIL because `downloadFit(...)` currently starts from legacy URLs only.

- [ ] **Step 3: Write the failing non-auth fallback regression**

Add a test that:

- constructs an activity with both `recordId` and usable legacy download fields
- makes the record-ID endpoint fail with a non-auth HTTP error such as `404`
- makes the next legacy direct URL succeed
- asserts `downloadFit(...)` falls back to the legacy URL path

- [ ] **Step 4: Run the fallback regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back to legacy direct download when recordId FIT endpoint fails non-auth"`

Expected: FAIL because the new primary path is not implemented.

- [ ] **Step 5: Write the failing empty-body regression**

Add a test that:

- makes the record-ID FIT endpoint return HTTP `200` with an empty byte body
- asserts `downloadFit(...)` throws a clear exception mentioning the empty FIT body

- [ ] **Step 6: Run the empty-body regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when the recordId FIT endpoint returns an empty body"`

Expected: FAIL for the expected reason.

- [ ] **Step 7: Implement the minimal record-ID-first download flow**

Update `lib/services/onelap_client.dart` to:

- try the authenticated `fit_content/{recordId}` path first when `activity.recordId` is present
- request bytes with `ResponseType.bytes`
- treat non-empty bytes as success
- reuse auth recovery helper for `401`/`403`
- fall back to existing legacy URL download flow on non-auth failure when legacy fields are available
- throw a clear empty-body exception when the record-ID endpoint succeeds with no bytes
- preserve existing dedup rename logic and OTM fallback for old activities

- [ ] **Step 8: Re-run the three focused download tests**

Run:

- `flutter test test/services/onelap_client_test.dart --plain-name "downloads FIT through the recordId OTM endpoint before trying legacy URLs"`
- `flutter test test/services/onelap_client_test.dart --plain-name "falls back to legacy direct download when recordId FIT endpoint fails non-auth"`
- `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when the recordId FIT endpoint returns an empty body"`

Expected: PASS.

## Task 6: Pin invalid list-payload handling and remove obsolete legacy-list tests

**Files:**
- Modify: `test/services/onelap_client_test.dart`
- Modify: `lib/services/onelap_client.dart`

- [ ] **Step 1: Replace the obsolete legacy `/analysis/list` regressions**

Remove or rewrite the current list tests that hardcode:

- `GET http://u.onelap.cn/analysis/list`
- legacy `fit_url` / `fitUrl` / `durl` list payload assumptions

Replace them with new list/detail tests already added above.

- [ ] **Step 2: Write the failing invalid-list-payload regression**

Add a test that:

- fakes login success
- fakes `POST /api/otm/ride_record/list` returning HTTP `200` with malformed shape such as `{"code":200,"data":[]}`
- asserts `listFitActivities(...)` throws a clear invalid-list exception

- [ ] **Step 3: Run the invalid-list regression to verify it fails**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when the OTM record list payload is invalid"`

Expected: FAIL for the expected reason.

- [ ] **Step 4: Implement the minimal invalid-list error contract**

Update `lib/services/onelap_client.dart` so malformed new list payloads throw a
clear exception instead of silently continuing or reusing legacy behavior.

- [ ] **Step 5: Re-run the invalid-list regression**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "throws a clear error when the OTM record list payload is invalid"`

Expected: PASS.

## Task 7: Re-run preserved legacy download regressions

**Files:**
- Modify: none
- Test: `test/services/onelap_client_test.dart`

- [ ] **Step 1: Run the direct URL fallback regression**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back from absolute durl to raw fit_url after 404"`

Expected: PASS.

- [ ] **Step 2: Run the fileKey fallback regression**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back to raw fileKey path after durl and raw fit urls 404"`

Expected: PASS.

- [ ] **Step 3: Run the secondary geo host regression**

Run: `flutter test test/services/onelap_client_test.dart --plain-name "falls back to secondary geo host after primary returns 404"`

Expected: PASS.

- [ ] **Step 4: Run the existing OTM fallback regressions that remain in scope**

Run:

- `flutter test test/services/onelap_client_test.dart --plain-name "falls back to OTM fit content download after standard URLs fail"`
- `flutter test test/services/onelap_client_test.dart --plain-name "uses absolute geo URL path for OTM fit content fallback"`
- `flutter test test/services/onelap_client_test.dart --plain-name "falls back to OTM fit content download for MATCH identifiers after standard URLs fail"`
- `flutter test test/services/onelap_client_test.dart --plain-name "does not treat unsupported identifiers as OTM fit content fallback candidates"`

Expected: PASS.

## Task 8: Run file-level and repository verification

**Files:**
- Modify: none

- [ ] **Step 1: Run the full `OneLapClient` test file**

Run: `flutter test test/services/onelap_client_test.dart`

Expected: PASS.

- [ ] **Step 2: Format touched files**

Run: `dart format lib test`

Expected: formatter completes successfully.

- [ ] **Step 3: Verify formatting is stable**

Run: `dart format --output=none --set-exit-if-changed lib test`

Expected: exit code 0.

- [ ] **Step 4: Run static analysis**

Run: `flutter analyze`

Expected: no new analyzer issues.

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`

Expected: PASS.

## Task 9: Prepare the change for review

**Files:**
- Modify: `lib/models/onelap_activity.dart`
- Modify: `lib/services/onelap_client.dart`
- Modify: `test/services/onelap_client_test.dart`

- [ ] **Step 1: Review scope control in the final diff**

Confirm the diff only contains:

- the additive `recordId` model field
- token bootstrap, refresh, and re-login recovery inside `OneLapClient`
- token-backed record list/detail parsing
- record-ID-first FIT download behavior
- the focused regression updates in `test/services/onelap_client_test.dart`

Confirm there is no unrelated cleanup or sync-engine refactor.

- [ ] **Step 2: Summarize verification evidence**

Capture the exact commands run and whether each passed:

- focused `flutter test --plain-name ...` checks from this plan
- `flutter test test/services/onelap_client_test.dart`
- `dart format ...`
- `flutter analyze`
- `flutter test`

- [ ] **Step 3: Commit only when explicitly requested**

If the user asks for a commit, stage only the intended files and create a
concise message such as:

`Fix OneLap token-based sync flow`
