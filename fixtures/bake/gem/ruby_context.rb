# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "bake/gem/shell"
require "json"
require "open3"
require "rbconfig"

module Bake
	module Gem
		# Runs repository code without changing the test process's directory or constants.
		module RubyContext
			def ruby(source)
				script = <<~RUBY
					output = $stdout.dup
					$stdout.reopen($stderr)
					result = begin
						#{source}
					end
					output.write(JSON.generate(result))
				RUBY
				
				# Load test dependencies from this project while executing in the fixture:
				environment = {"RUBYOPT" => nil, "BUNDLE_GEMFILE" => File.expand_path("../../../gems.rb", __dir__)}
				output, errors, status = Open3.capture3(environment, RbConfig.ruby, "-rbundler/setup", "-rjson", "-e", script, chdir: root)
				raise CommandExecutionError.new(errors, status) unless status.success?
				JSON.parse(output, symbolize_names: true)
			end
		end
	end
end
