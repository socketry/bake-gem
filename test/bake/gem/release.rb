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
	
	def bake(*arguments)
		isolated_ruby(<<~RUBY, chdir: root)
			require "bake/context"
			Bake::Context.load.call(*#{arguments.inspect})
		RUBY
	end
	
	def prepare
		bake("gem:release:branch:patch")
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
	
	it "reports gem metadata through the task" do
		expect(bake("gem:metadata")).to be == {name: "example", version: "1.0.0", version_path: "lib/example/version.rb"}
		File.delete(File.join(root, "example.gemspec"))
		expect{bake("gem:metadata")}.to raise_exception(RuntimeError, message: be =~ /No gemspec found/)
	end
	
	it "commits the version and hook output on the current branch" do
		result = bake("gem:release:version:minor")
		expect(result[:version].to_s).to be == "1.1.0"
		expect(result[:version_path]).to be == "lib/example/version.rb"
		expect(git("branch", "--show-current")).to be == "main"
		expect(git("status", "--porcelain")).to be == ""
		expect(git("show", "HEAD:releases.md")).to be == "1.1.0\nFirst change"
		expect(File).not.to be(:exist?, File.join(root, "obsolete.md"))
	end
	
	it "validates a release through the task" do
		prepare
		result = bake("gem:release:validate", "base=#{@base}")
		expect(result).to have_keys(version: be == "1.0.1", base: be == @base, commit: be == git("rev-parse", "HEAD"))
	end
	
	it "rejects prereleases and incomplete version numbers" do
		expect{@release.bump("1.0.0", "1.0.1-alpha")}.to raise_exception(RuntimeError, message: be =~ /stable three-part versions/)
		expect{@release.bump("1.0", "1.0.1")}.to raise_exception(RuntimeError, message: be =~ /stable three-part versions/)
	end
	
	it "removes the temporary worktree when generation fails" do
		worktree = nil
		expect do
			@release.worktree(@base) do |path|
				worktree = path
				File.write(File.join(path, "partial.txt"), "Partial output")
				raise "Generation failed"
			end
		end.to raise_exception(RuntimeError, message: be == "Generation failed")
		expect(File).not.to be(:exist?, worktree)
		expect(git("worktree", "list", "--porcelain")).not.to be(:include?, worktree)
	end
	
	it "accepts a signing key path and produces a verifiable signed gem" do
		key = OpenSSL::PKey::RSA.new(2048)
		certificate = Gem::Security.create_cert_email("test@example.com", key)
		write("release.cert", certificate.to_pem)
		write("release.pem", key.to_pem)
		gemspec_path = File.join(root, "example.gemspec")
		File.write(gemspec_path, File.read(gemspec_path).sub('spec.summary = "Example"', 'spec.summary = "Example"; spec.cert_chain = ["release.cert"]'))
		path = bake("gem:build", "signing_key=#{File.join(root, 'release.pem')}")
		package = Gem::Package.new(path, Gem::Security::Policy.new("Release Test", only_trusted: false))
		expect(package.verify).to be_truthy
		expect(OpenSSL::X509::Certificate.new(package.spec.cert_chain.last).to_der).to be == certificate.to_der
	end
	
	it "requires a signing key when requested and permits unsigned builds" do
		expect{bake("gem:build", "signing_key=true")}.to raise_exception(ArgumentError, message: be =~ /Signing key is required/)
		path = bake("gem:build", "signing_key=false")
		expect(Gem::Package.new(path).spec.cert_chain).to be == []
	end
	
	it "publishes the local release commit and only its intended tag" do
		write(".gitignore", "remote.git/\npkg/\n")
		commit("Configure local remote")
		git("init", "--bare", "remote.git")
		git("remote", "add", "origin", File.join(root, "remote.git"))
		git("push", "--set-upstream", "origin", "main")
		git("tag", "unrelated")
		result = isolated_ruby(<<~RUBY, chdir: root)
			require "bake/context"
			context = Bake::Context.load
			helper = context.lookup("gem:release").instance.helper
			published = nil
			helper.define_singleton_method(:push_gem) {|path:| published = Gem::Package.new(path).spec.version.to_s}
			result = context.call("gem:release:patch")
			result.merge(published: published)
		RUBY
		expect(result).to have_keys(tag: be == "v1.0.1", published: be == "1.0.1")
		expect(git("--git-dir=remote.git", "tag")).to be == "v1.0.1"
		expect(git("--git-dir=remote.git", "rev-parse", "main")).to be == git("rev-parse", "HEAD")
		expect(git("--git-dir=remote.git", "rev-parse", "v1.0.1")).to be == git("rev-parse", "HEAD")
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
	
	it "rejects an existing release tag before modifying files" do
		git("tag", "v1.0.1")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /tag v1.0.1 already exists/)
		expect(git("branch", "--show-current")).to be == "main"
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
	
	it "rejects package output generated by hooks before staging it" do
		write("bake.rb", "def after_gem_release_version_increment(version); File.write(\"example.gem\", \"Package\"); end\n")
		base = commit("Packaging hook")
		expect{prepare}.to raise_exception(RuntimeError, message: be =~ /build output/)
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
