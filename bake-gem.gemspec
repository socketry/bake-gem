# frozen_string_literal: true

require_relative "lib/bake/gem/version"

Gem::Specification.new do |spec|
	spec.name = "bake-gem"
	spec.version = Bake::Gem::VERSION
	
	spec.summary = "Release management for Ruby gems."
	spec.authors = ["Samuel Williams", "Copilot"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/ioquatix/bake-gem"
	
	spec.metadata = {
		"bug_tracker_uri" => "https://github.com/ioquatix/bake-gem/issues",
		"changelog_uri" => "https://github.com/ioquatix/bake-gem/blob/main/releases.md",
		"documentation_uri" => "https://ioquatix.github.io/bake-gem/",
		"funding_uri" => "https://github.com/sponsors/ioquatix/",
		"source_code_uri" => "https://github.com/ioquatix/bake-gem.git",
	}
	
	spec.files = Dir.glob(["{bake,context,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.3"
	
	spec.add_dependency "console", "~> 1.25"
end
