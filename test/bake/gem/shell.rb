# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2024-2026, by Samuel Williams.

require "bake/gem/shell"
require "sus/fixtures/console/null_logger"

class ShellTest
	include Bake::Gem::Shell
end

describe Bake::Gem::Shell do
	include Sus::Fixtures::Console::NullLogger
	
	let(:shell) {ShellTest.new}
	
	with "#system" do
		it "can run shell commands" do
			expect(shell.system("true")).to be_truthy
		end
		
		it "raises an error if the command fails" do
			expect{shell.system("false")}.to raise_exception(Bake::Gem::CommandExecutionError) do |error|
				expect(error.status).to be == 1
			end
		end
	end
	
	with "#execute" do
		it "can run shell commands and capture output" do
			shell.execute("echo", "Hello, World!") do |input|
				expect(input.read).to be == "Hello, World!\n"
			end
		end
		
		it "raises an error if the command fails" do
			expect{shell.execute("false"){|input| input.read}}.to raise_exception(Bake::Gem::CommandExecutionError) do |error|
				expect(error.exit_code).to be == 1
			end
		end
	end
	
	with "#readlines" do
		it "can run shell commands and capture output as lines" do
			expect(shell.readlines("echo", "Hello, World!")).to be == ["Hello, World!\n"]
		end
	end
end
