# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require_relative "helper"
require "json"
require "tmpdir"

module Bake
	module Gem
		# Regenerates release content from its base without modifying the checkout.
		class Release
			include Shell
			
			# Supported stable version increments.
			BUMPS = {"patch" => [nil, nil, 1], "minor" => [nil, 1, 0], "major" => [1, 0, 0]}.freeze
			
			# @parameter root [String] The repository containing the commits to compare.
			def initialize(root)
				@root = File.expand_path(root)
			end
			
			# Resolve a commit before passing it to other Git commands.
			def resolve(reference)
				git("rev-parse", "--verify", "--end-of-options", "#{reference}^{commit}").strip
			end
			
			# Yield a temporary detached worktree and remove it even on failure.
			def worktree(reference)
				commit = resolve(reference)
				Dir.mktmpdir("bake-gem-release-") do |directory|
					path = File.join(directory, "source")
					system("git", "worktree", "add", "--detach", path, commit, chdir: @root, out: File::NULL)
					begin
						yield path
					ensure
						system("git", "worktree", "remove", "--force", path, chdir: @root, out: File::NULL)
					end
				end
			end
			
			# Run Bake tasks in a fresh interpreter, avoiding cached version constants.
			# @parameter path [String] The checkout in which to run the tasks.
			# @parameter arguments [Array(String)] Task names and command line arguments.
			# @parameter options [Hash] Task options; nil values use the task defaults.
			def bake(path, *arguments, **options)
				Dir.mktmpdir("bake-gem-result-") do |directory|
					result = File.join(directory, "result.json")
					options.each{|key, value| arguments << "#{key}=#{value}" unless value.nil?}
					system("bake", *arguments, "output", "file=#{result}", "format=json", chdir: path, severity: :debug)
					JSON.parse(File.read(result), symbolize_names: true)
				end
			end
			
			# Inspect a committed gem in isolation.
			def metadata(reference)
				worktree(reference) {|path| bake(path, "gem:metadata")}
			end
			
			# Validate an ordinary patch, minor, or major transition.
			def bump(previous, target)
				unless previous.match?(/\A\d+\.\d+\.\d+\z/) && target.match?(/\A\d+\.\d+\.\d+\z/)
					raise "Release validation supports stable three-part versions only."
				end
				BUMPS.each do |name, increment|
					version = Version.new(previous.split(".").map(&:to_i), nil).increment(increment)
					return name if version.join == target
				end
				raise "Unsupported release transition: #{previous} -> #{target}."
			end
			
			# Compare an independently generated release tree to the candidate, including added and deleted files.
			# @parameter base [String] Current target commit, or the merged commit's first parent when publishing.
			# @parameter candidate [String] Proposed or merged release commit.
			# @parameter optional [Boolean] Allow ordinary PRs which do not change the version.
			def validate(base:, candidate: "HEAD", optional: false)
				base = resolve(base)
				candidate = resolve(candidate)
				proposed = metadata(candidate)
				worktree(base) do |path|
					previous = bake(path, "gem:metadata")
					raise "Release changes the gem name." unless proposed[:name] == previous[:name]
					return nil if optional && proposed[:version] == previous[:version]
					increment = bump(previous[:version], proposed[:version])
					generated = bake(path, "gem:release:version:increment", BUMPS.fetch(increment).join(","))
					raise "Generated version does not match proposal." unless generated[:version] == proposed[:version]
					system("git", "add", "--all", chdir: path)
					expected = readlines("git", "write-tree", chdir: path).join.strip
					diff = git("diff", "--no-ext-diff", "--no-textconv", candidate, expected, "--")
					raise "Release content is stale or contains unrelated changes. Expected changes:\n#{diff}" unless diff.empty?
					return proposed.merge(base: base, commit: candidate, bump: increment)
				end
			end
			
			private
			
			def git(*arguments)
				readlines("git", *arguments, chdir: @root).join
			end
		end
	end
end
