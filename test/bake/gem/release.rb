# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/gem/helper"
require "bake/gem/release"
require "sus/fixtures/console/null_logger"
require "sus/fixtures/isolated_ruby_context"
require "sus/fixtures/temporary_directory_context"
require "open3"

describe Bake::Gem::Release do
	include Sus::Fixtures::Console::NullLogger
	include Sus::Fixtures::TemporaryDirectoryContext
	include Sus::Fixtures::IsolatedRubyContext
	
	def git(*arguments)
		output, status = Open3.capture2e("git", *arguments, chdir: @root)
		raise output unless status.success?
		output.strip
	end
	
	def write(path, content)
		FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
		File.write(File.join(@root, path), content)
	end
	
	def commit(message)
		git("add", "--all")
		git("commit", "-m", message)
		git("rev-parse", "HEAD")
	end
	
	def prepare
		isolated_ruby(<<~RUBY, chdir: root)
			require "bake/context"
			Bake::Context.load.call("gem:release:branch:patch")
		RUBY
	end
	
	def around
		super do
			git("init", "--initial-branch=main")
			git("config", "core.hooksPath", File::NULL)
			git("config", "user.name", "Release Test")
			git("config", "user.email", "test@example.com")
			write("lib/example/version.rb", "module Example; VERSION = \"1.0.0\"; end\n")
			write("example.gemspec", <<~RUBY)
				require_relative "lib/example/version"
				Gem::Specification.new do |spec|
					spec.name = "example"
					spec.version = Example::VERSION
					spec.summary = "Example"
					spec.authors = ["Test"]
					spec.files = Dir.glob("lib/**/*")
				end
			RUBY
			write("changes.md", "First change\n")
			write("obsolete.md", "Removed by hook\n")
			write("bake.rb", <<~RUBY)
				def after_gem_release_version_increment(version)
					File.write("releases.md", version.join + "\\n" + File.read("changes.md"))
					File.delete("obsolete.md")
				end
			RUBY
			@base = commit("Initial source")
			@release = subject.new(@root)
			yield
		end
	end
	
	it "creates a local branch and commits every hook output without tags or remotes" do
		result = prepare
		expect(result[:branch]).to be == "releases/v1.0.1"
		expect(result[:version_path]).to be == "lib/example/version.rb"
		expect(git("status", "--porcelain")).to be == ""
		expect(git("tag")).to be == ""
		expect(git("show", "HEAD:releases.md")).to be == "1.0.1\nFirst change"
		expect(File).not.to be(:exist?, File.join(@root, "obsolete.md"))
		expect(@release.validate(base: @base)[:version]).to be == "1.0.1"
	end
	
	it "builds the committed version even when the caller has loaded the old version" do
		result = isolated_ruby(<<~RUBY, chdir: root)
			require "bake/gem/release"
			require "./lib/example/version"
			release = Bake::Gem::Release.new(Dir.pwd)
			release.bake(Dir.pwd, "gem:release:branch:patch")
			package_path = release.worktree("HEAD") do |path|
				release.bake(path, "gem:build", root: File.join(Dir.pwd, "packages with spaces"), signing_key: false)
			end
			{loaded_version: Example::VERSION, package_path: package_path}
		RUBY
		expect(result[:loaded_version]).to be == "1.0.0"
		
		package = Gem::Package.new(result[:package_path])
		package.extract_files(File.join(@root, "extracted"))
		expect(package.spec.version.to_s).to be == "1.0.1"
		expect(File.read(File.join(@root, "extracted/lib/example/version.rb"))).to be(:include?, 'VERSION = "1.0.1"')
	end
	
	it "rejects a dirty checkout before changing branch or version" do
		write("unrelated.txt", "Uncommitted")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /uncommited/)
		expect(git("branch", "--show-current")).to be == "main"
		expect(File.read(File.join(@root, "lib/example/version.rb"))).to be(:include?, "1.0.0")
	end
	
	it "rejects branch collisions before modifying files" do
		git("branch", "releases/v1.0.1")
		expect{prepare}.to raise_exception(Bake::Gem::CommandExecutionError)
		expect(git("status", "--porcelain")).to be == ""
	end
	
	it "rejects detached preparation before modifying files" do
		git("checkout", "--detach")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /branch checkout/)
		expect(git("status", "--porcelain")).to be == ""
	end
	
	it "rejects a missing version constant without creating a branch" do
		write("lib/example/version.rb", "module Example; VERSION = [1, 0, 0].join(\".\"); end\n")
		commit("Change version representation")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /Could not find version number/)
		expect(git("branch", "--show-current")).to be == "main"
	end
	
	it "leaves failed hook changes available without committing or publishing" do
		write("bake.rb", "def after_gem_release_version_increment(version); File.write(\"partial.md\", \"Partial\"); raise \"Hook failed\"; end\n")
		base = commit("Broken hook")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /Hook failed/)
		expect(git("rev-parse", "HEAD")).to be == base
		expect(File).to be(:exist?, File.join(@root, "partial.md"))
	end
	
	it "rejects private keys generated by hooks before staging them" do
		write("bake.rb", "def after_gem_release_version_increment(version); File.write(\"release.pem\", \"-----BEGIN PRIVATE KEY-----\"); end\n")
		base = commit("Unsafe hook")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /private key/)
		expect(git("rev-parse", "HEAD")).to be == base
		expect(git("diff", "--cached", "--name-only")).to be == ""
	end
	
	it "accepts an updated base when regenerated content is unchanged" do
		prepare
		git("checkout", "main")
		write("unrelated.txt", "New main content")
		base = commit("Independent change")
		git("checkout", "releases/v1.0.1")
		git("rebase", "main")
		expect(@release.validate(base: base)[:version]).to be == "1.0.1"
	end
	
	it "rejects stale notes after a successful rebase" do
		prepare
		git("checkout", "main")
		write("changes.md", "First change\nNew change\n")
		base = commit("More release notes")
		git("checkout", "releases/v1.0.1")
		git("rebase", "main")
		expect{@release.validate(base: base)}.to raise_exception(RuntimeError, message: be =~ /New change/)
		expect(git("status", "--porcelain")).to be == ""
	end
	
	it "rejects unrelated additions and deletions in a release" do
		prepare
		write("unexpected.txt", "Surprise")
		commit("Unexpected file")
		expect{@release.validate(base: @base)}.to raise_exception(RuntimeError, message: be =~ /unexpected.txt/)
	end
	
	it "validates a squash commit against its first parent even after main advances" do
		prepare
		git("checkout", "main")
		git("merge", "--squash", "releases/v1.0.1")
		merged = commit("Release version 1.0.1")
		write("later.txt", "Later development")
		commit("Continue development")
		expect(@release.validate(base: "#{merged}^1", candidate: merged)[:commit]).to be == merged
	end
	
	it "skips ordinary PRs only when explicitly requested" do
		expect(@release.validate(base: @base, optional: true)).to be_nil
		expect{@release.validate(base: @base)}.to raise_exception(RuntimeError, message: be =~ /Unsupported release transition/)
	end
end
