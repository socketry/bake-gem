# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2026, by Samuel Williams.
# Copyright, 2025, by Copilot.

# Initialize the gem context with helper for gem operations.
# @parameter context [Bake::Context] The bake execution context.
def initialize(context)
	super(context)
	
	require_relative "../lib/bake/gem/helper"
	
	@helper = Bake::Gem::Helper.new(context.root)
end

attr :helper

# List all the files that will be included in the gem:
def files
	@helper.gemspec.files
end

# Inspect the gem name, version, and version file in the current checkout.
def metadata
	gemspec = @helper.gemspec
	raise "No gemspec found." unless gemspec
	
	return {name: gemspec.name, version: gemspec.version.to_s, version_path: @helper.version_path}
end

# Build the gem into the pkg directory.
# @parameter root [String] The root directory to build the gem into. Defaults to `pkg`.
# @parameter signing_key [String | Nil] A signing key path, "true" to require signing, or "false" to disable signing.
def build(root: "pkg", signing_key: nil)
	# Accept boolean command line options while preserving signing key paths:
	signing_key = true if signing_key == "true"
	signing_key = false if signing_key == "false"
	
	@helper.build_gem(root: root, signing_key: signing_key)
end

# Build and install the gem into system gems.
# @parameter local [Boolean] only use locally available caches.
def install(local: false)
	changes = @helper.uncommitted_changes
	
	if changes.any?
		Console.warn(self, "Installing from clean git worktree; uncommitted changes are not included in the installed gem.", changes: changes.map(&:chomp))
	end
	
	# For installing the gem, don't bother with signing it:
	path = @helper.build_gem_in_worktree(signing_key: false)
	
	arguments = []
	arguments << "--local" if local
	
	@helper.install_gem(*arguments, path: path)
	
	return {
		name: @helper.gemspec.name,
		version: @helper.gemspec.version,
		package_path: path,
	}
end

# Release the gem by building it, pushing it to the server, and tagging the release.
# @parameter tag [Boolean] Whether to tag the release.
def release(tag: true)
	@helper.guard_clean
	
	version = @helper.gemspec.version
	current_branch = @helper.current_branch
	
	tag_name = @helper.create_release_tag(tag: tag, version: version)
	
	begin
		path = @helper.build_gem_in_worktree
		@helper.push_gem(path: path)
	rescue => error
		@helper.delete_git_tag(tag_name) if tag_name
		raise
	end
	
	@helper.push_release(current_branch: current_branch, tag: tag_name)
	context["after_gem_release"]&.call(name: @helper.gemspec.name, version: version, tag: tag_name, path: path)
	
	return {
		name: @helper.gemspec.name,
		version: @helper.gemspec.version,
		package_path: path,
		tag: tag_name,
	}
end
