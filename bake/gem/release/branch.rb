# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

# Increment the patch number of the current version.
def patch
	commit([nil, nil, 1], message: "Bump patch version.")
end

# Increment the minor number of the current version.
def minor
	commit([nil, 1, 0], message: "Bump minor version.")
end

# Increment the major number of the current version.
def major
	commit([1, 0, 0], message: "Bump major version.")
end

# Increments the version and commits the changes into a new branch.
#
# @parameter bump [Array(Integer | Nil)] the version bump to apply before publishing, e.g. `0,1,0` to increment minor version number.
# @parameter message [String] the git commit message to use.
def commit(bump, message: "Bump version.")
	release = context.lookup("gem:release")
	helper = release.instance.helper
	helper.guard_clean
	helper.guard_last_commit_not_version_bump
	path = helper.version_path or raise "Could not find version file!"
	line = File.read(File.expand_path(path, helper.root))
	version = nil
	Bake::Gem::Version.update_version(line){|current| version = current.increment(bump)}
	raise "Could not find version number!" unless version
	branch_name = helper.create_release_branch(version: version.join)
	result = context.lookup("gem:release:version:increment").call(bump, message: message)
	helper.commit_version_changes(message: message)
	return result.merge(branch: branch_name)
end
