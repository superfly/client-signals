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

  # Server-side integrations remain optional so the core signal-detection API
  # has no runtime dependencies. See elixir/AGENTS.md.
  defp deps do
    [
      {:plug, "~> 1.14", optional: true},
      {:opentelemetry_api, "~> 1.4", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:prom_ex, "~> 1.11", optional: true}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/superfly/client-signals"}
    ]
  end
end
