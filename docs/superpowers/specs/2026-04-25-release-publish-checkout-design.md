## Summary

- Fix the GitHub Actions `Android Release` workflow so tag-triggered `publish` can create or update GitHub Releases successfully.
- Keep the existing build and release publication flow unchanged except for providing the repository context required by `gh release`.

## Problem

- The `publish` job currently downloads the built APK artifact and then runs `gh release view`, `gh release create`, or `gh release upload`.
- That job does not check out the repository first.
- In GitHub Actions, `gh release` is being executed from a directory that is not a git repository, and it fails with `fatal: not a git repository`.

## Goal

- Make tag-triggered release publication succeed for the existing `v1.0.12` test case and future release tags.

## Non-Goals

- Do not change tag parsing, build version derivation, artifact naming, release notes placeholder text, or publish behavior beyond fixing this failure.
- Do not modify unrelated workflow files or app code.

## Approach

- Add `actions/checkout@v4` near the start of the `publish` job.
- Leave the rest of the job unchanged.

## Why This Approach

- This is the smallest fix that restores the repository context expected by the GitHub CLI.
- It avoids hardcoding `--repo` on every `gh` command and keeps the workflow easier to maintain.

## Verification

- Update the workflow in an isolated worktree.
- Re-run or re-trigger the `Android Release` workflow for `v1.0.12` after the fix is available on the target branch.
- Confirm that:
  - the `publish` job succeeds,
  - GitHub Release `v1.0.12` exists,
  - the release includes `app-release.apk`.
