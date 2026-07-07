defmodule ClientSignals.MixProject do
  use Mix.Project

  def project do
    [
      app: :client_signals,
      version: "0.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: [],
      description: "Privacy-safe client signals for CLI HTTP traffic.",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/superfly/client-signals"}
    ]
  end
end
