# Sync Banner Platform Deduped Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show per-platform sync outcomes correctly in the "just synced" detail dialog, including explicit skipped/deduped counts, without relying on a misleading overall success/failure summary.

**Architecture:** Keep the existing sync flow and banner storage model, but extend `SyncSummary` and `SyncResultBanner` with per-platform deduped counts so the detail dialog can render each platform independently. Fix the dialog UI to remove the aggregate row and show platform chips for success, failure, and skipped using the requested colors.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Lock the broken summary behavior with tests

**Files:**
- Modify: `test/services/sync_engine_test.dart`

- [ ] **Step 1: Write the failing test**

Add a regression test covering one activity where Strava is already uploaded and Xingzhe fails. Assert the summary keeps per-platform counts separate and records `stravaDeduped == 1` instead of hiding Strava.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/sync_engine_test.dart --plain-name "tracks platform deduped counts separately from failures"`

Expected: FAIL because `SyncSummary` does not expose per-platform deduped counts yet.

- [ ] **Step 3: Write minimal implementation**

Extend the summary model and sync engine accounting to track per-platform deduped counts.

- [ ] **Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

### Task 2: Lock the dialog rendering with a widget test

**Files:**
- Create: `test/models/sync_result_banner_test.dart`

- [ ] **Step 1: Write the failing test**

Add a focused test for `SyncResultBanner.toSyncSummary()` and banner-facing data that proves Strava skipped state remains visible and labeled independently from Xingzhe failure details.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/sync_result_banner_test.dart`

Expected: FAIL because deduped counts are not serialized or reconstructed yet.

- [ ] **Step 3: Write minimal implementation**

Add deduped fields to `SyncSummary` and `SyncResultBanner` JSON/model conversion.

- [ ] **Step 4: Run test to verify it passes**

Run the same command and confirm PASS.

### Task 3: Update the detail dialog presentation

**Files:**
- Modify: `lib/models/sync_summary.dart`
- Modify: `lib/models/sync_result_banner.dart`
- Modify: `lib/services/sync_engine.dart`
- Modify: `lib/screens/home_screen.dart`

- [ ] **Step 1: Implement the smallest UI change**

Remove the aggregate success/failure row from `_showBannerDetail()`. In each platform section, render chips for:
- success: green
- failed: red
- deduped/skipped: white

Always keep the platform heading visible when that platform has any success, failure, or deduped count.

- [ ] **Step 2: Keep the rest of the banner behavior unchanged**

Do not refactor unrelated banner list or sync-history code.

### Task 4: Verify the fix

**Files:**
- Test: `test/services/sync_engine_test.dart`
- Test: `test/models/sync_result_banner_test.dart`

- [ ] **Step 1: Run focused tests**

Run: `flutter test test/services/sync_engine_test.dart`

Run: `flutter test test/models/sync_result_banner_test.dart`

- [ ] **Step 2: Run broader verification**

Run: `flutter test`

Expected: PASS.
