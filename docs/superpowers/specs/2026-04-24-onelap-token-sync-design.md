# OneLap Token Sync Design

## Goal

Restore OneLap sync after the web client migrated away from the legacy
`/analysis/list` session flow.

The app should keep the current user experience: users still enter their OneLap
username and password in settings, and sync should transparently use the new
token-based record APIs under the hood.

## Current State

`lib/services/onelap_client.dart` currently mixes two old assumptions:

- login succeeds through `POST https://www.onelap.cn/api/login`
- activities can then be listed through `GET http://u.onelap.cn/analysis/list`

This no longer matches the live OneLap web flow.

Investigation against the live site confirmed:

1. `www.onelap.cn/login.html` still logs in with account + MD5 password through
   `POST /api/login`
2. the login response data now contains `token` and `refresh_token`
3. the modern `u.onelap.cn` app uses `Authorization` headers, not the old
   cross-subdomain session assumption
4. sports records are fetched through
   `POST /api/otm/ride_record/list`
5. FIT downloads are available through
   `GET /api/otm/ride_record/analysis/fit_content/{id}`

The current client fails before sync starts because `_fetchActivitiesPayload()`
still requests the legacy HTML endpoint and treats the HTML response as a login
failure.

## Approaches Considered

### 1. Recommended: keep username/password UX and migrate internals to tokens

Continue storing OneLap username and password in settings. Change
`OneLapClient` so it:

- logs in to obtain `token` and `refresh_token`
- calls the new OTM record list API with `Authorization`
- refreshes or re-logins when the token stops working
- downloads FIT files through the new record download API

Pros:

- no settings UX change
- smallest user-visible change
- aligns with the live web client

Cons:

- requires moderate `OneLapClient` refactor and new tests

### 2. Token-only configuration

Expose OneLap `token` and `refresh_token` as settings and stop using password
login for sync.

Pros:

- smallest networking change in code

Cons:

- poor user experience
- token acquisition becomes manual and fragile
- not aligned with the confirmed desired UX

### 3. Dual-mode support

Support both username/password login and token-only configuration.

Pros:

- most flexible

Cons:

- adds complexity in validation, storage, and tests
- unnecessary for the scoped recovery fix

## Chosen Approach

Use approach 1.

The app should preserve the current settings flow while replacing the outdated
record-fetch logic with the same token-driven API family used by the live OneLap
web app.

## Scope

Included:

- replace legacy record listing with token-based OTM record listing
- keep account/password login as the only user-facing OneLap auth input
- support token refresh or re-login when token-based requests fail due to auth
- switch FIT download to the modern record download API when record IDs are
  available
- add focused regression tests around login, record listing, token refresh, and
  FIT download

Excluded:

- settings UI redesign
- new persisted settings keys for OneLap token fields
- broad sync engine refactors outside OneLap client integration
- unrelated Strava upload, dedupe, or state-store behavior changes

## Design Details

### Files

- `lib/services/onelap_client.dart`
- `lib/models/onelap_activity.dart`
- `test/services/onelap_client_test.dart`

### OneLap auth state inside `OneLapClient`

`OneLapClient` should own a small in-memory auth state:

- access token
- refresh token
- whether token-backed auth has been initialized for the current client

This state remains internal to the client. The initial fix does not persist
tokens to secure storage because the current app already persists username and
password and can re-login as needed.

### Login flow

`login()` should stop being a pure validation call and become the canonical
token bootstrap step.

Expected behavior:

1. `POST {baseUrl}/api/login` with:
   - `account: username`
   - `password: md5(password)`
2. accept success codes already supported by the client (`0` or `200`)
3. extract the first element of `payload['data']`
4. read `token` and `refresh_token`
5. fail with a clear exception if either required field is missing
6. cache both values inside the client instance

This keeps settings validation behavior intact because the settings screen only
needs `login()` to complete successfully.

### Token-backed request helper

Add a small internal request path for OTM record APIs:

- ensure the client has a valid token before the request
- attach `Authorization: <token>`
- if the request returns an auth failure, first try token refresh
- if refresh is unavailable or fails, perform a fresh login and retry once

Refresh should mirror the live web app contract:

- `POST /api/token`
- body: `{"token": refreshToken, "from": "web", "to": "web"}`
- treat the refresh as successful only when the HTTP response is `200` and the
  JSON payload has `code == 200`
- read the refreshed auth fields from `payload['data']`
- require a non-empty `token`
- replace the cached refresh token only when the response also includes a new
  non-empty `refresh_token`

Auth retry behavior should stay narrow: one refresh/re-login recovery path per
request, no unbounded loops.

Auth failure recognition for the new OTM APIs should be explicit:

- HTTP `401`
- HTTP `403`

Do not treat every `422` as an auth failure. A `422` from the new APIs should be
surfaced as a normal request error unless later evidence proves it is part of
the auth lifecycle.

For the scoped fix, tests should cover the concrete triggers we can model with
confidence: `403` refresh, then re-login fallback when refresh cannot recover.

### Record list fetch

Replace `_fetchActivitiesPayload()` legacy logic with a token-backed call to:

- `POST /api/otm/ride_record/list`

The request body should use the same paging shape observed in the live web app:

- `page: 1`
- `limit: 50`

Pagination strategy for this fix is intentionally scoped to a single page.

`listFitActivities()` should request only the first page (`page: 1`) and keep
the existing practical ceiling of at most 50 recent records, matching the
current method contract (`limit = 50`) instead of introducing new multi-page
sync behavior in the same change.

The raw HTTP response contract should be treated as:

- top-level JSON object with `code == 200` for success
- top-level `data` object containing the record payload consumed by the web app

Inside `payload['data']`, the response contract used by the app should be:

- `list` contains the record array
- `pagination` may contain paging metadata such as `total`

Each list item should be mapped into `OneLapActivity` using the confirmed web
record fields:

- `id` -> stable activity identifier
- `start_riding_time` -> start time
- `name` when present, otherwise derive a deterministic fallback filename from
  `start_riding_time`
- `id` -> record download identity for FIT retrieval

The minimal implementation should not depend on legacy `fit_url`, `fitUrl`,
`durl`, or `fileKey` fields being present in the new list payload.

To preserve dedupe compatibility with already-synced records as much as possible,
`listFitActivities()` should enrich each retained record through:

- `GET /api/otm/ride_record/analysis/{id}`

The detail call should reuse the same token-backed auth helper and attempt to
recover legacy download identity fields from the detail payload in the existing
priority order:

- top-level JSON object with `code == 200` for success
- top-level `data` object containing the detail payload

1. `fileKey`
2. `fit_url`
3. `fitUrl`
4. `durl`

If one of those legacy fields is present, keep using the existing style of
`recordKey` derived from that field so previously persisted fingerprints remain
matchable. Only fall back to `recordId:<id>` when the detail payload does not
expose any legacy-compatible key.

If the detail request fails for a non-auth transport or HTTP reason, continue
building the activity with `recordKey = recordId:<id>` so sync can still
proceed. If the detail request succeeds but the payload shape is invalid, throw
a clear exception because that indicates an unexpected contract change.

### Model compatibility

`OneLapActivity` should gain one additive optional field:

- `recordId`

Mapping rules:

- set `recordId` from the new record list item's `id`
- keep `activityId` as the string form of that same `id`
- populate `recordKey` from recovered legacy detail fields when available
- otherwise fall back to `recordId:<id>`
- keep legacy FIT-related fields optional and unchanged for older flows

`downloadFit(...)` should use `recordId` as the canonical identity for the new
record-ID-based FIT endpoint. Existing callers and tests should continue to work
because the field is additive and optional.

`login()` caller impact is intentionally narrow. The only production caller is
the OneLap settings validation path in `lib/screens/settings_screen.dart`, which
only requires `login()` to succeed or throw. Caching auth state inside the
client instance is therefore safe for this scoped fix and should be covered by
tests that verify repeated authenticated calls reuse or refresh cached auth.

### FIT download flow

`downloadFit(...)` should prefer the modern record download path when the
activity has a record identifier compatible with:

- `GET /api/otm/ride_record/analysis/fit_content/{id}`

The request should use the cached token-backed auth helper.

The success response contract for the modern FIT endpoint should be treated as a
raw byte stream, not a JSON envelope.

Expected success characteristics:

- Dio requests the endpoint with `responseType: ResponseType.bytes`
- `response.data` is the FIT byte array
- any non-empty byte body is treated as a successful FIT download

Behavior must be deterministic:

1. if the activity has a record download identifier, try the modern
   `/api/otm/ride_record/analysis/fit_content/{id}` path first
2. if that request fails with a recoverable auth failure, use the auth recovery
   path and retry once
3. if the activity does not have a record download identifier, fall back to the
   existing direct URL download flow
4. if the record-ID path fails for a non-auth reason and the activity also has
   legacy direct download fields, fall back to the existing direct URL flow
5. keep the existing OTM fallback behavior for legacy activities that still use
   the old field shapes

### Error handling

Keep current behavior where the sync engine receives actionable exceptions.

Add explicit error messages for:

- login response missing `token`
- login response missing `refresh_token`
- token refresh failure when retrying authenticated requests
- invalid record-list payloads from the new API
- empty FIT download bodies from the new endpoint

Risk-control detection for the new OTM list API is explicitly out of scope for
this fix because the investigation did not reveal an equivalent modern response
shape. Do not invent new heuristics. Preserve existing risk-control handling in
legacy code paths only.

## Testing

Add focused tests in `test/services/onelap_client_test.dart`.

Required regression coverage:

1. `login()` succeeds only when the login payload includes both token fields
2. `login()` fails with a clear exception when token data is missing
3. `listFitActivities()` uses the new token-backed record list endpoint and maps
   the response into `OneLapActivity`
4. `listFitActivities()` uses the per-record detail endpoint to recover a
   legacy-compatible `recordKey` when the detail payload exposes one
5. an authenticated request that initially fails with `403` refreshes the token
   and succeeds on retry
6. when refresh cannot recover an authenticated request, the client performs one
   fresh login and retries once
7. `downloadFit(...)` uses the new record FIT endpoint when the activity has the
   required record identifier
8. `downloadFit(...)` falls back to the legacy direct URL flow when the record
   download path fails for a non-auth reason and legacy fields are available
9. invalid record-list or detail payloads from the new APIs throw clear
   exceptions
10. empty FIT download bodies from the new endpoint throw a clear exception
11. existing legacy fallback tests continue to pass unless they are intentionally
   replaced by the new primary flow

The tests should use fake Dio transports and assert the exact request URLs,
methods, and headers where practical.

## Risks And Mitigations

### Risk: guessed record-list payload shape is incomplete

Mitigation:

- keep parsing minimal and evidence-driven
- add fixtures from observed live API fields only
- make additive model changes instead of rewriting sync flow

### Risk: token refresh contract differs from the live app in small details

Mitigation:

- mirror the live frontend request body exactly
- cover refresh retry behavior through narrow unit tests
- fall back to re-login when refresh cannot recover the request

### Risk: modern FIT download identity differs between records

Mitigation:

- keep model changes optional and additive
- prefer the new record-ID path for known-good records
- preserve existing direct-download fallback only when it remains low-cost

## Verification

Before claiming the fix works, run:

- focused `OneLapClient` tests for login, listing, refresh, and download
- `dart format lib test`
- `flutter analyze`
- `flutter test`

## Open Questions

No blocking questions remain for the scoped recovery fix.
