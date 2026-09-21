# Releases

## Unreleased

  - Prepare release branches with `gem:release:branch:patch/minor/major`, committing the version bump and all release-hook changes before review.
  - Add `gem:release:validate` to detect stale generated release content and unrelated changes.
  - Build committed source in a fresh Ruby process and accept an explicit signing key path with `gem:build`.
  - Push only the intended release tag when publishing locally.
  - Invoke release tasks directly with `bake` in the worktree and log internal invocations only at debug level (`CONSOLE_LEVEL=debug`).

## v0.13.1

  - Better `version.rb` detection in `version_path` method.

## v0.13.0

  - Add `after_gem_release` hook for post-release actions.

## v0.12.0

  - Add `guard_last_commit_not_version_bump` method to prevent consecutive version bumps.
  - Add `build_gem_in_worktree` method for building gems in isolated git worktrees.
  - Improve shell command execution with better error handling and specific exit code access.

## v0.11.1

  - Better integration with `bake`'s default output.

## v0.11.0

  - Improved bake task return values.

## v0.10.0

  - Better handling of versions.

## v0.9.0

  - Add `after_gem_release_version_increment` hook.
