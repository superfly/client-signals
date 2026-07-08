defmodule ClientSignals.MixProject do
  use Mix.Project

  def project do
    [
      app: :client_signals,
      version: "0.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Privacy-safe client signals for CLI HTTP traffic.",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # :plug and :opentelemetry_api are optional: the core signal-detection API
  # has no runtime dependencies, but including apps that already depend on
  # both (e.g. a Phoenix app) can use ClientSignals.Plug, which is only
  # defined when both are loaded. See elixir/AGENTS.md.
  defp deps do
    [
      {:plug, "~> 1.14", optional: true},
      {:opentelemetry_api, "~> 1.4", optional: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/superfly/client-signals"}
    ]
  end
end
