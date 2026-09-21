# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2026, by Samuel Williams.
# Copyright, 2025, by Copilot.

require "rubygems"
require "rubygems/package"
require "fileutils"
require "tmpdir"

require_relative "shell"

module Bake
	module Gem
		# Represents a gem version with support for parsing and incrementing version numbers.
		class Version
			LINE_PATTERN = /VERSION = ['"](?<version>(?<parts>\d+\.\d+\.\d+)(-(?<suffix>.*?))?)['"]/
			
			# If the line contains a version constant, update it using the provided block.
			def self.update_version(line)
				if match = line.match(LINE_PATTERN)
					parts = match[:parts].split(/\./).map(&:to_i)
					suffix = match[:suffix]
					
					version = self.new(parts, suffix)
					
					yield version
					
					line.sub!(match[:version], version.join)
				end
			end
			
			# Initialize a new version with the given parts and optional suffix.
			# @parameter parts [Array(Integer)] The version number parts (e.g., [1, 2, 3] for "1.2.3").
			# @parameter suffix [String | Nil] The optional version suffix (e.g., "alpha", "beta").
			def initialize(parts, suffix)
				@parts = parts
				@suffix = suffix
			end
			
			# Check if this version represents a release version.
			# @returns [Boolean] True if the version has no suffix, indicating it's a release version.
			def release?
				@suffix.nil?
			end
			
			# Join all parts together to form a version string.
			def join
				if @suffix
					return "#{@parts.join('.')}-#{@suffix}"
				else
					return @parts.join(".")
				end
			end
			
			# The version string with a "v" prefix.
			def to_s
				"v#{join}"
			end
			
			# Increment the version according to the provided bump specification.
			# @parameter bump [Array(Integer | Nil)] Array specifying how to increment each version part.
			# @returns [Version] Self, for method chaining.
			def increment(bump)
				bump.each_with_index do |increment, index|
					if index > @parts.size
						@suffix = bump[index..].join(".")
						break
					end
					
					if increment == 1
						@parts[index] += 1
					elsif increment == 0
						@parts[index] = 0
					end
					# If increment is nil, we don't change that part of the version
				end
				
				return self
			end
		end
		
		# Helper class for performing gem-related operations like building, installing, and publishing gems.
		class Helper
			include Shell
			
			# Initialize a new helper with the specified root directory and optional gemspec.
			# @parameter root [String] The root directory of the gem project.
			# @parameter gemspec [Gem::Specification | Nil] The gemspec to use, or nil to find it automatically.
			def initialize(root = Dir.pwd, gemspec: nil)
				@root = File.expand_path(root)
				@gemspec = gemspec || find_gemspec
			end
			
			# @attribute [String] The root directory of the gem project.
			attr :root
			
			# @attribute [Gem::Specification] The gemspec for the gem.
			attr :gemspec
			
			# Find the path to the version.rb file in the gem.
			# @returns [String | Nil] The path to the version file, or nil if not found.
			def version_path
				if @gemspec
					candidates = @gemspec.files.grep(/lib(.*?)\/version.rb/)
					
					# If only one version file exists, use it:
					return candidates.first if candidates.size == 1
					
					# Try to match the gem name convention (e.g., "protocol-rack" -> "lib/protocol/rack/version.rb"):
					expected_path = "lib/#{@gemspec.name.gsub('-', '/')}/version.rb"
					return expected_path if candidates.include?(expected_path)
					
					# Fall back to the shortest path (most likely to be the main gem version):
					return candidates.min_by(&:length)
				end
			end
			
			# Update the version number in the version file according to the bump specification.
			# @parameter bump [Array(Integer)] Array specifying how to increment each version part.
			# @parameter version_path [String] The path to the version file.
			# @returns [String | Boolean] The path to the version file if updated, or false if no version file found.
			def update_version(bump, version_path = self.version_path)
				return false unless version_path
				
				# Guard against consecutive version bumps
				guard_last_commit_not_version_bump
				
				path = File.expand_path(version_path, @root)
				lines = File.readlines(path)
				new_version = nil
				
				lines.each do |line|
					Version.update_version(line) do |version|
						new_version = version.increment(bump)
					end
				end
				
				if new_version
					File.write(path, lines.join)
					
					if block_given?
						yield new_version
					end
					
					return version_path
				end
			end
			
			# Verify that the repository has no uncommitted changes.
			# @returns [Boolean] True if the repository is clean.
			# @raises [RuntimeError] If there are uncommitted changes in the repository.
			def guard_clean
				lines = uncommitted_changes
				
				if lines.any?
					raise "Repository has uncommited changes!\n#{lines.join('')}"
				end
				
				return true
			end
			
			# Get the list of uncommitted changes in the repository.
			# @returns [Array(String)] The porcelain status lines for uncommitted changes.
			def uncommitted_changes
				readlines("git", "status", "--porcelain", chdir: @root)
			end
			
			# Verify that the last commit was not a version bump.
			# @returns [Boolean] True if the last commit was not a version bump.
			# @raises [RuntimeError] If the last commit was a version bump.
			def guard_last_commit_not_version_bump
				# Get the last commit message:
				begin
					last_commit_message = readlines("git", "log", "-1", "--pretty=format:%s", chdir: @root).first&.strip
				rescue CommandExecutionError => error
					# If git log fails (e.g., no commits yet), skip the check:
					if error.exit_code == 128
						return true
					else
						raise
					end
				end
				
				if last_commit_message && last_commit_message.match?(/^Bump (patch|minor|major|version)( version)?\.?$/i)
					raise "Last commit appears to be a version bump: #{last_commit_message.inspect}. Cannot bump version consecutively."
				end
				
				return true
			end
			
			# @parameter root [String] The root path for package files.
			# @parameter signing_key [String | Nil] The signing key to use for signing the package.
			# @returns [String] The path to the built gem package.
			def build_gem(root: "pkg", signing_key: nil)
				# Ensure the output directory exists:
				root = File.expand_path(root, @root)
				FileUtils.mkdir_p(root)
				
				output_path = File.join(root, @gemspec.file_name)
				
				if signing_key == false
					@gemspec.signing_key = nil
				elsif signing_key.is_a?(String)
					@gemspec.signing_key = signing_key
				elsif signing_key == true and @gemspec.signing_key.nil?
					raise ArgumentError, "Signing key is required for signing the gem, but none was specified by the gemspec."
				end
				
				Dir.chdir(@root) do
					::Gem::Package.build(@gemspec, false, false, output_path)
				end
			end
			
			# Install the gem using the `gem install` command.
			# @parameter arguments [Array] Additional arguments to pass to `gem install`.
			# @parameter path [String] The path to the gem file to install.
			def install_gem(*arguments, path: @gemspec.file_name)
				system("gem", "install", path, *arguments)
			end
			
			# Push the gem to a gem repository using the `gem push` command.
			# @parameter arguments [Array] Additional arguments to pass to `gem push`.
			# @parameter path [String] The path to the gem file to push.
			def push_gem(*arguments, path: @gemspec.file_name)
				system("gem", "push", path, *arguments)
			end
			
			# Build the gem in a clean worktree for better isolation
			# @parameter root [String] The root path for package files.
			# @parameter signing_key [String | Nil] The signing key to use for signing the package.
			# @returns [String] The path to the built gem package.
			def build_gem_in_worktree(root: "pkg", signing_key: nil)
				original_pkg_path = File.expand_path(root, @root)
				
				# Create a unique temporary path for the worktree
				timestamp = Time.now.strftime("%Y%m%d-%H%M%S-%N")
				worktree_path = File.join(Dir.tmpdir, "bake-gem-build-#{timestamp}")
				
				begin
					# Create worktree from current HEAD
					unless system("git", "worktree", "add", "--detach", worktree_path, "HEAD", chdir: @root)
						raise "Failed to create git worktree. Make sure you have at least one commit in the repository."
					end
					
					# Build using the worktree's gemspec in a fresh interpreter:
					require_relative "release"
					output_path = Release.new(@root).bake(worktree_path, "gem:build", root: original_pkg_path, signing_key: signing_key)
					
					output_path
				ensure
					# Clean up the worktree
					system("git", "worktree", "remove", worktree_path, "--force", chdir: @root)
				end
			end
			
			# Create a release branch before generating release changes.
			# @parameter version [String] The proposed release version.
			# @returns [String] The name of the created branch.
			def create_release_branch(version:)
				guard_clean
				raise "Release preparation requires a branch checkout." unless current_branch
				branch_name = "releases/v#{version}"
				raise "Release tag v#{version} already exists." unless readlines("git", "tag", "--list", "v#{version}", chdir: @root).empty?
				
				system("git", "checkout", "-b", branch_name, chdir: @root)
				
				return branch_name
			end
			
			# Commit version changes to the current branch.
			# @parameter message [String] The commit message to use.
			def commit_version_changes(message: "Bump version.")
				guard_release_changes
				system("git", "add", "--all", chdir: @root)
				system("git", "commit", "-m", message, chdir: @root)
			end
			
			# Reject generated package output and private keys before staging release changes.
			def guard_release_changes
				paths = readlines("git", "diff", "--name-only", "--diff-filter=ACM", "-z", "HEAD", chdir: @root).join.split("\0")
				paths.concat(readlines("git", "ls-files", "--others", "--exclude-standard", "-z", chdir: @root).join.split("\0"))
				paths.uniq.each do |path|
					raise "Release changes include build output: #{path}" if path.start_with?("pkg/") || path.end_with?(".gem")
					absolute = File.expand_path(path, @root)
					next unless File.file?(absolute) && !File.symlink?(absolute)
					if File.binread(absolute).match?(/^-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----/)
						raise "Release changes include a private key: #{path}"
					end
				end
			end
			
			# Fetch remote tags and create a release tag for the specified version.
			# @parameter tag [Boolean] Whether to tag the release.
			# @parameter version [String] The version to tag.
			# @returns [String | Nil] The tag name if created, nil otherwise.
			def create_release_tag(tag: true, version:)
				tag_name = nil
				
				if tag
					tag_name = "v#{version}"
					system("git", "fetch", "--all", "--tags", chdir: @root)
					system("git", "tag", tag_name, chdir: @root)
				end
				
				return tag_name
			end
			
			# Delete a git tag.
			# @parameter tag_name [String] The name of the tag to delete.
			def delete_git_tag(tag_name)
				system("git", "tag", "--delete", tag_name, chdir: @root)
			end
			
			# Push changes and tags to the remote repository.
			# @parameter current_branch [String | Nil] The current branch name, or nil if not on a branch.
			def push_release(current_branch: nil, tag: nil)
				# If we are on a branch, push, otherwise just push the tags (assuming shallow checkout):
				if current_branch
					system("git", "push", chdir: @root)
				end
				
				system("git", "push", "origin", "refs/tags/#{tag}", chdir: @root) if tag
			end
			
			# Figure out if there is a current branch, if not, return `nil`.
			# @returns [String | Nil] The current branch name, or nil if not on a branch.
			def current_branch
				# We originally used this but it is not supported by older versions of git.
				# readlines("git", "branch", "--show-current").first&.chomp
				
				readlines("git", "symbolic-ref", "--short", "--quiet", "HEAD", chdir: @root).first&.chomp
			rescue CommandExecutionError
				nil
			end
			
			# Find a gemspec file in the root directory.
			# @parameter glob [String] The glob pattern to use for finding gemspec files.
			# @returns [Gem::Specification | Nil] The loaded gemspec, or nil if none found.
			# @raises [RuntimeError] If multiple gemspec files are found.
			def find_gemspec(glob = "*.gemspec")
				paths = Dir.glob(glob, base: @root).sort
				
				if paths.size > 1
					raise "Multiple gemspecs found: #{paths}, please specify one!"
				end
				
				if path = paths.first
					return Dir.chdir(@root){::Gem::Specification.load(File.expand_path(path, @root))}
				end
			end
		end
	end
end
