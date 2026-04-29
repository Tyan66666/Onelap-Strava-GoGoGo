## Summary

This spec covers the minimum follow-up changes for PR #4 on top of `SethShen/main`, implemented on a separate branch. The scope is intentionally limited to the three review blockers already identified: missing package dependencies for the new Xingzhe client, sensitive credential/session logging, and sync history record collisions for failures that do not have a fingerprint.

## Goals

- Restore compile/testability for the new Xingzhe integration by declaring all directly imported packages.
- Remove credential and session leakage from production logs while keeping actionable error reporting.
- Preserve multiple failed sync history entries instead of overwriting them when the fingerprint is empty.

## Non-Goals

- No UI redesign or behavior changes outside the three blockers.
- No broad lint cleanup in `sync_engine.dart` or other files.
- No changes to Android build baseline issues unrelated to this PR.

## Design

### 1. Dependency declaration fix

`lib/services/xingzhe_client.dart` currently imports `pointycastle`, `encrypt`, and `http_parser`, but `pubspec.yaml` does not declare them. Add these packages to `dependencies` so analyzer and test compilation can resolve the new Xingzhe code.

### 2. Sensitive log removal

The Xingzhe client currently logs session IDs, cookies, usernames, and encrypted password output. Replace those logs with either no log output or coarse, non-sensitive progress logs.

This branch must not log or throw raw cookies, session IDs, usernames, passwords, encrypted passwords, auth headers, or raw response bodies. Error reporting may keep status codes and fixed sanitized summaries only.

### 3. Stable history dedupe key for failed records

`StateStore.saveSyncRecords()` currently deduplicates only by `fingerprint`. Failed download/fingerprint-generation records use an empty fingerprint, so later failures overwrite earlier ones. `StateStore.loadSyncRecords()` also merges by `fingerprint`, so the same collision currently happens on read.

Change the history identity logic so that both save-time replacement and load-time merge use the same rule:

- non-empty fingerprints still deduplicate by fingerprint, preserving existing behavior
- empty-fingerprint records use the explicit fallback key `startTime + sourceFilename`, so distinct failures remain distinct without changing normal re-upload merging for real fingerprints

This keeps re-upload merging semantics for real fingerprints while preventing unrelated failed entries from collapsing into a single history row.

## Testing

- Add a focused regression test for the empty-fingerprint history collision in `StateStore` behavior, proving that two empty-fingerprint records with different `startTime` and/or `sourceFilename` survive both save and load as two distinct history entries.
- Run `flutter analyze`.
- Run `flutter test`.

## Implementation Notes

- Work continues on branch `review/pr-4-fixups`, created from `SethShen/main` in the isolated review worktree.
- Keep the patch small and avoid unrelated formatting or refactoring changes.
