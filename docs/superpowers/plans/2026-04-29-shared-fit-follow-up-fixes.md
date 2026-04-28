# Shared FIT Follow-up Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three review findings in shared FIT upload flow without widening scope.

**Architecture:** Keep the existing shared upload path centered in `SharedFitUploadService`, and close the behavior gaps by reusing the same persistence and rewrite conventions as `SyncEngine`. Add narrow regression tests first, then implement the minimum production changes to keep share uploads, history, and later dedupe checks consistent.

**Tech Stack:** Flutter, Dart, flutter_test

---

### Task 1: Add failing shared-upload regression tests

**Files:**
- Modify: `test/services/shared_fit_upload_service_test.dart`

- [ ] **Step 1: Write a failing test for dedupe-state persistence after shared uploads**
- [ ] **Step 2: Run that test and verify it fails for the expected reason**
- [ ] **Step 3: Write a failing test proving deduped history entries do not keep red error text**
- [ ] **Step 4: Run that test and verify it fails for the expected reason**
- [ ] **Step 5: Write a failing test proving GCJ rewrite receives `RewriteOptions` in share flow**
- [ ] **Step 6: Run that test and verify it fails for the expected reason**

### Task 2: Implement the minimum production fixes

**Files:**
- Modify: `lib/services/shared_fit_upload_service.dart`

- [ ] **Step 1: Persist dedupe state for successful or already-uploaded shared platform results**
- [ ] **Step 2: Avoid storing duplicate/idempotent messages in `errorMessage` for deduped history rows**
- [ ] **Step 3: Forward `RewriteOptions(startTime, sourceFilename)` when rewriting shared FIT files**

### Task 3: Verify the fixes end to end

**Files:**
- Modify if needed: `test/services/shared_fit_upload_service_test.dart`

- [ ] **Step 1: Run the targeted shared upload test file and confirm all tests pass**
- [ ] **Step 2: Run `flutter analyze` and confirm no analyzer issues**
- [ ] **Step 3: Run `flutter test` and confirm the full suite passes**
