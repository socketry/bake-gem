# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2026, by Samuel Williams.
# Copyright, 2025, by Copilot.

source "https://rubygems.org"

gemspec

group :maintenance, optional: true do
	# gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	
	gem "agent-context"
	
	gem "utopia-project"
	
	gem "decode"
end

group :test do
	gem "sus", "~> 0.38"
	gem "covered"
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-console"
	
	gem "bake-test"
end
