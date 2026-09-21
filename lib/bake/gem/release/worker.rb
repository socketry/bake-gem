# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

# Internal subprocess entry point. Repository files are executable code; callers
# must keep PR validation separate from jobs with publishing credentials.
require "json"
request = JSON.parse(File.read(ARGV.fetch(0)), symbolize_names: true)
$LOAD_PATH.replace(request.fetch(:load_path))
require_relative "../helper"
options = request.fetch(:options)
helper = Bake::Gem::Helper.new(Dir.pwd)
raise "No gemspec found." unless helper.gemspec

result = case request.fetch(:action)
when "metadata"
	{name: helper.gemspec.name, version: helper.gemspec.version.to_s, version_path: helper.version_path}
when "build"
	helper.build_gem(**options)
when "prepare"
	require "bake/context"
	registry = Bake::Registry::Aggregate.new
	request.fetch(:gems).each{|path| registry.append_path(path)}
	registry.append_path(File.expand_path("../../../..", __dir__))
	registry.append_path(Dir.pwd)
	registry.append_bakefile(File.expand_path("bake.rb")) if File.file?("bake.rb")
	context = Bake::Context.new(registry, Dir.pwd)
	context.bakefile
	prepared = context.lookup("gem:release:version:increment").call(options.fetch(:bump))
	helper.guard_release_changes
	prepared
else
	raise "Unknown release worker action."
end

File.write(request.fetch(:result), JSON.generate(result))
