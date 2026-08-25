# frozen_string_literal: true

require "json"
require "minitest/autorun"

require_relative "../lib/client_signals"
require_relative "../lib/client_signals/request"

module FixtureHelpers
  # The shared fixtures at the repository root are the contract; every language
  # package is held to the same files.
  def fixture(name)
    JSON.parse(File.read(File.expand_path("../../spec/#{name}", __dir__)))
  end

  def signals_from_fixture(raw)
    ClientSignals::Signals.new(
      interactive: raw["interactive"],
      parent: raw["parent"],
      agent: raw["agent"],
      agent_source: raw["agentSource"],
      ci: raw["ci"],
    )
  end

  # ENV.replace would clobber anything the test runner itself relies on, so
  # swap in a copy and put the original back.
  def with_env(vars)
    original = ENV.to_h
    ENV.replace(vars)
    yield
  ensure
    ENV.replace(original)
  end
end
