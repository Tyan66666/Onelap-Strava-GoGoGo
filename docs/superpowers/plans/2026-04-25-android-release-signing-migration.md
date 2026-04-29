# Android Release Signing Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Android release APKs use one stable signing identity across local builds and GitHub Actions so existing users can upgrade in place.

**Architecture:** Verify that the current machine's historical signing key matches a shipped install, back it up, and migrate that same key identity into a project-specific release keystore. Then make Gradle and GitHub Actions read only that canonical release signing configuration for release builds.

**Tech Stack:** Flutter, Gradle Kotlin DSL, Java keytool, GitHub Actions, GitHub Secrets

---

### Task 1: Verify and back up the historical signing identity

**Files:**
- Verify: `~/.android/debug.keystore`
- Create: local secure backup outside repo

- [ ] **Step 1: Read the current local keystore fingerprint**

Run a certificate inspection command against `~/.android/debug.keystore` and record the SHA-256 fingerprint.

- [ ] **Step 2: Compare against a historical APK or installed app**

Inspect at least one previously distributed APK or the currently installed app certificate fingerprint.
Expected: it matches the local debug-keystore fingerprint.

- [ ] **Step 3: Stop if fingerprints do not match**

If the fingerprints differ, do not continue the migration. Recover the actual historical signing key first.

- [ ] **Step 4: Back up the source keystore**

Copy `~/.android/debug.keystore` to a secure backup location outside the repository before any migration step.

### Task 2: Create the canonical project release keystore

**Files:**
- Create: `android/app/upload-keystore.jks` (local, untracked)

- [ ] **Step 1: Migrate the same key identity into a project keystore**

Use `keytool -importkeystore` or equivalent to move the existing private key into `android/app/upload-keystore.jks`.

- [ ] **Step 2: Use project-specific strong passwords**

Assign strong passwords for the destination keystore and key entry.

- [ ] **Step 3: Verify migrated keystore fingerprint**

Inspect `android/app/upload-keystore.jks`.
Expected: the SHA-256 fingerprint matches the source signing identity exactly.

### Task 3: Fail release builds until canonical signing is configured

**Files:**
- Modify: `.gitignore`
- Modify: `android/app/build.gradle.kts`
- Create: `android/key.properties.example` or equivalent documented template

- [ ] **Step 1: Write the failing expectation**

Define the desired behavior: release builds must read signing info from `android/key.properties` and fail fast when the file or keystore is missing.

- [ ] **Step 2: Update gitignore for local signing artifacts**

Ignore `android/key.properties` and `android/app/upload-keystore.jks`.

- [ ] **Step 3: Implement Gradle signing config**

Update `android/app/build.gradle.kts` so release signing is loaded from `android/key.properties` and `android/app/upload-keystore.jks`.

- [ ] **Step 4: Remove debug fallback for release**

Release builds must no longer use `signingConfigs.getByName("debug")`.

- [ ] **Step 5: Add local setup template**

Create a tracked example file documenting the expected key properties entries without real secrets.

### Task 4: Verify local release signing behavior

**Files:**
- Verify: local build outputs only

- [ ] **Step 1: Run a release build with canonical signing**

Run: `flutter build apk --release --dart-define=FLUTTER_IMPELLER_ENABLED=false`
Expected: build succeeds using the configured project keystore.

- [ ] **Step 2: Inspect the built APK certificate**

Read the signing certificate fingerprint from the generated APK.
Expected: it matches the historical signing identity.

- [ ] **Step 3: Run focused verification commands**

Run: `flutter analyze`
Run: `flutter test`
Expected: both succeed.

### Task 5: Make GitHub Actions use the same signing identity

**Files:**
- Modify: `.github/workflows/android-release.yml`
- Document: required GitHub Secrets names in repo docs or setup template

- [ ] **Step 1: Add workflow inputs for signing material restoration**

Define the canonical secret contract for CI:
- base64 keystore secret
- keystore password
- key password
- key alias

- [ ] **Step 2: Restore keystore and key properties in CI**

Before the build step, write `android/app/upload-keystore.jks` and `android/key.properties` from secrets.

- [ ] **Step 3: Make CI fail fast without signing secrets**

The workflow must not silently build a differently signed release APK.

### Task 6: Verify CI release signing continuity end to end

**Files:**
- Verify: GitHub Actions run and produced release APK

- [ ] **Step 1: Configure GitHub Secrets**

Set the repository secrets required by the workflow.

- [ ] **Step 2: Push the fix and trigger a new tag release**

Create a fresh test tag after the workflow changes land on `main`.

- [ ] **Step 3: Inspect the CI-generated APK signature**

Download the release asset or artifact and read its certificate fingerprint.
Expected: it matches the historical signing identity.

- [ ] **Step 4: Verify device upgrade behavior**

Install the new APK over the existing installed app on the phone.
Expected: upgrade succeeds without uninstalling first.
