## Summary

- Fix Android release installation incompatibility by making all future release APKs use a stable signing key.
- Preserve upgrade compatibility for existing users by continuing to sign with the same private key identity that previous locally built releases used.
- Improve security by migrating that existing key into a project-specific release keystore with stronger secret management.

## Problem

- The current Android `release` build type is signed with `signingConfigs.getByName("debug")`.
- Local builds on the developer machine and GitHub Actions builds do not reliably use the same keystore file, so APK signatures can differ between environments.
- Android rejects installing an update when the package name matches but the signing certificate does not.
- The user already has existing users in the field and does not want to force uninstall/reinstall.

## Goal

- Keep the signing identity compatible with existing locally distributed APKs.
- Make local release builds and GitHub Actions release builds use the same signing key every time.
- Avoid committing keystore material or plaintext secrets into the repository.

## Non-Goals

- Do not rotate to a brand new signing key.
- Do not change package name, versioning scheme, or release workflow behavior beyond the signing path.
- Do not introduce Play App Signing or app bundle publishing in this change.

## Assumptions

- Historical user-installed APKs may have been built on this machine and signed by the current local `~/.android/debug.keystore` private key, but this must be verified before migration.
- The user has access to this machine, so the existing key material can be read locally and migrated.
- If any historical APKs were signed by a different machine or key, those specific installs still will not be upgrade-compatible.

## Recommended Approach

### 1. Preserve the current signing identity

- Before any migration, create a secure backup copy of the current local `~/.android/debug.keystore` and record its certificate fingerprint.
- First validate that the existing local Android debug keystore on this machine actually matches at least one previously distributed APK or the currently installed app certificate fingerprint.
- Only after that validation, treat this key as the source of truth for the current signing identity.
- If the fingerprints do not match, stop the migration immediately and recover the actual historical signing key instead of proceeding with this machine's current debug keystore.
- Export or migrate the same key into a project-specific release keystore so the private key identity stays the same.

### 2. Create a project-specific release keystore container

- Generate a new keystore file for this project that contains the same signing key pair.
- Protect that keystore with strong, project-specific passwords instead of relying on the default debug-keystore conventions.

### 3. Update Android Gradle signing configuration

- Replace the hardcoded `release -> debug signingConfig` setup.
- Define a single signing contract for release builds:
  - local secrets live in `android/key.properties` and a canonical untracked keystore file at `android/app/upload-keystore.jks`,
  - `android/key.properties` and `android/app/upload-keystore.jks` are gitignored,
  - Gradle reads the release signing values only from that local configuration.
- Make the `release` build type use the project release keystore exclusively.
- Release builds must fail fast when signing material is missing; there is no fallback to debug signing for release.

### 4. Update GitHub Actions to restore signing secrets

- Store the release keystore as a base64-encoded GitHub Actions secret.
- Store keystore passwords and alias as separate GitHub Actions secrets.
- In the Android release workflow, restore the keystore file to `android/app/upload-keystore.jks` before `flutter build apk --release`, generate or provide `android/key.properties`, and inject the signing values expected by Gradle.

### 5. Verify signing continuity

- Capture the certificate fingerprint of the current local signing key before migration.
- Capture the certificate fingerprint from at least one historical distributed APK or from the currently installed app on the target phone.
- Confirm those fingerprints match before proceeding with the migration.
- Build a locally signed release APK using the new configuration.
- Confirm the new APK certificate fingerprint matches the old signing identity.
- Publish a new test tag and verify that the GitHub Actions APK is signed with the same certificate.
- Install that APK over the existing installed app on the target phone to confirm in-place upgrade compatibility.

## Why This Approach

- It preserves the only signing identity most likely to match what existing users already have installed.
- It removes CI environment drift by making release signing explicit and deterministic.
- It improves operational security over continuing to rely on an ad hoc debug keystore workflow.

## Risks

- If earlier user releases came from a different machine or different keystore, those users still cannot upgrade in place.
- If the local debug keystore is lost before migration is completed, upgrade compatibility for existing users is effectively lost.
- Secret handling must be correct; exposing the migrated keystore would compromise the signing identity.

## Verification

- Compare the current local debug-keystore fingerprint with a historical shipped APK or installed app fingerprint before migration.
- Compare old and new signing certificate fingerprints locally.
- Run the release workflow with the new signing setup.
- Inspect the generated APK signing certificate from CI output or downloaded artifact.
- Confirm a phone with the currently installed app can install the new APK as an upgrade without uninstalling first.
