# frozen_string_literal: true

require_relative "lib/client_signals/version"

Gem::Specification.new do |spec|
  spec.name = "client_signals"
  spec.version = ClientSignals::VERSION
  spec.authors = ["Fly.io"]

  spec.summary = "Privacy-safe client signals for CLI HTTP traffic."
  spec.description = <<~DESC
    Coarse, privacy-safe signals that help estimate whether traffic is driven by
    a human or an AI agent, plus the bounded server-side classification of the
    Fly-Client-* headers they produce. For aggregate observability only.
  DESC
  spec.homepage = "https://github.com/superfly/client-signals"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "source_code_uri" => "https://github.com/superfly/client-signals",
    "rubygems_mfa_required" => "true",
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
