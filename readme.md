# Bake::Gem

Provides bake tasks for common gem release workflows.

[![Development Status](https://github.com/ioquatix/bake-gem/workflows/Test/badge.svg)](https://github.com/ioquatix/bake-gem/actions?workflow=Test)

## Usage

Please see the [project documentation](https://ioquatix.github.io/bake-gem/) for more details.

  - [Getting Started](https://ioquatix.github.io/bake-gem/guides/getting-started/index) - This guide explains how to use `bake-gem` to release gems safely and efficiently.

## Releases

Please see the [project releases](https://ioquatix.github.io/bake-gem/releases/index) for all releases.

### v0.15.0

  - Prepare release branches with `gem:release:branch:patch/minor/major`, committing the version bump and all release-hook changes before review.
  - Add `gem:release:validate` to detect stale generated release content and unrelated changes.
  - Build committed source in a fresh Ruby process and accept an explicit signing key path with `gem:build`.
  - Push only the intended release tag when publishing locally.

### v0.13.1

  - Better `version.rb` detection in `version_path` method.

### v0.13.0

  - Add `after_gem_release` hook for post-release actions.

### v0.12.0

  - Add `guard_last_commit_not_version_bump` method to prevent consecutive version bumps.
  - Add `build_gem_in_worktree` method for building gems in isolated git worktrees.
  - Improve shell command execution with better error handling and specific exit code access.

### v0.11.1

  - Better integration with `bake`'s default output.

### v0.11.0

  - Improved bake task return values.

### v0.10.0

  - Better handling of versions.

### v0.9.0

  - Add `after_gem_release_version_increment` hook.

## See Also

  - [Bake](https://github.com/ioquatix/bake) — The bake task execution tool.

## Contributing

We welcome contributions to this project.

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature.'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create a new pull request.

### Running Tests

To run the test suite:

``` bash
$ bundle exec sus
```

### Making Releases

To make a new release:

``` bash
$ bundle exec bake gem:release:patch # or minor or major
```

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
