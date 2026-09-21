# Getting Started

This guide explains how to use `bake-gem` to release gems safely and efficiently.

## Installation

Add the `bake-gem` gem to your project:

``` bash
$ bundle add bake-gem
```

You may prefer to keep it in a separate `maintenance` group:

``` ruby
group :maintenance, optional: true do
	gem "bake-gem"
end
```

## Usage

Before using `bake-gem`, ensure you have:

1. A properly configured `gemspec` file in your project root
2. A clean git repository (no uncommitted changes)
3. Your gem's version file (typically `lib/your_gem/version.rb`)
4. RubyGems credentials configured for publishing

### Local Release Process

The most typical process for releasing a gem locally:

``` bash
$ bake gem:release:patch
```

This single command will:
1. **Guard against consecutive version bumps** - Prevents accidentally bumping version twice
2. **Check repository cleanliness** - Ensures no uncommitted changes
3. **Increment the patch version** - Updates your version file (e.g., 1.0.0 → 1.0.1)
4. **Commit the version change** - Creates a commit with the version bump
5. **Build the gem in a clean worktree** - Isolates the build process
6. **Push to RubyGems** - Publishes your gem
7. **Create and push git tags** - Tags the release

### Version Increment Options

Choose the appropriate version increment for a complete release:

``` bash
# For bug fixes (1.0.0 -> 1.0.1)
$ bake gem:release:patch

# For new features (1.0.0 -> 1.1.0)
$ bake gem:release:minor

# For breaking changes (1.0.0 -> 2.0.0)
$ bake gem:release:major
```

For more control, you can also use the traditional two-step process:

``` bash
# Step 1: Bump version and commit
$ bake gem:release:version:patch  # or minor/major

# Step 2: Build and release
$ bake gem:release
```

## Advanced Workflows

### Automated CI/CD Pipeline

Use `bake-gem-github` for GitHub pull requests, native approval rules, Trusted Publishing and attestations. The provider-independent preparation tasks below work identically locally and in CI.

#### Step 1: Create Release Branch (Locally)

``` bash
# Create a release branch with version bump
$ bake gem:release:branch:patch  # or minor/major
```

This will:
- Require a clean checkout on a branch
- Create a new branch named `releases/v[new-version]` before modifying files
- Bump the gem version
- Run `after_gem_release_version_increment` and commit all changes, including added and deleted documentation

This task does not push, open a PR, create tags or publish. Select a current base before running it; the GitHub companion additionally fetches and checks the default branch. Failed hooks leave changes available for inspection.

#### Step 2: Release from CI (After Merge)

The GitHub companion handles publishing the exact merged commit. To independently validate release content, supply the current target commit and proposed commit:

``` bash
$ bundle exec bake gem:release:validate base=origin/main candidate=HEAD
```

Validation creates a temporary checkout of the base, applies the proposed patch/minor/major bump, runs the same hooks, and compares the complete generated tree with the candidate. It never bumps the candidate again or modifies your checkout. Stale notes and unexpected file additions/deletions fail with a diff. A rebase passes when the generated content still matches. Hooks must be repeatable for the same source and version.

For an ordinary PR check, add `optional=true` to accept candidates without a version change. After merge, use the merged commit's first parent as `base` and the merged commit as `candidate`; later changes on `main` do not affect that release boundary.

### Individual Commands

You can also run individual steps:

``` bash
# Just build the gem
$ bake gem:build

# Install the gem locally for testing
$ bake gem:install

# List files that will be included in the gem
$ bake gem:files

# Inspect the gem name, version, and version file as JSON
$ bake gem:metadata output format=json

# Build without signing
$ bake gem:build signing_key=false
```

## Safety Features

`bake-gem` includes several safety features:

### Consecutive Version Bump Prevention
The tool automatically prevents consecutive version bumps by checking the last commit message. If the last commit was already a version bump (e.g., "Bump patch version."), it will raise an error.

### Clean Worktree Building
Gems are built in isolated git worktrees to ensure the build environment exactly matches your committed code, preventing issues with uncommitted changes affecting the build.

Builds and release validation run Bake tasks in fresh Ruby processes so version constants and hook state come from each checkout.

### Repository Cleanliness Check
Before any release operation, the tool ensures your repository has no uncommitted changes.

## Configuration

### Gem Signing

To sign your gems, ensure your gemspec includes:

``` ruby
spec.signing_key = "path/to/private_key.pem"
spec.cert_chain = ["path/to/certificate.pem"]
```

To supply a signing key when building:

``` bash
$ bake gem:build signing_key=/path/to/private_key.pem
```

Or disable signing explicitly:

``` bash
$ bake gem:build signing_key=false
```

### RubyGems Configuration

For automated releases, set these environment variables:

``` bash
export RUBYGEMS_HOST=https://rubygems.org  # or your private gem server
export GEM_HOST_API_KEY=your_api_key
```

## Examples

### Complete Release Example

``` bash
# 1. Ensure clean repository
$ git status

# 2. Run tests
$ bundle exec rake test  # or your test command

# 3. Release with patch version increment (single command)
$ bake gem:release:patch

# Output:
# Updated version: v1.2.4
# Successfully built RubyGem
# Name: my-gem
# Version: 1.2.4
# File: my-gem-1.2.4.gem
# Pushing gem to https://rubygems.org...
# Tagged: v1.2.4
```

### Branch-based Release Example

``` bash
# Create release branch
$ bake gem:release:branch:minor
# Creates branch: releases/v1.3.0
# Commits the version bump and release-hook output
# Leaves the branch local for inspection

# Validate before pushing or opening a PR:
$ bake gem:release:validate base=main
```
