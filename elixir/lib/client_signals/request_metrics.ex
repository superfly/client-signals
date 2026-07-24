defmodule ClientSignals.RequestMetrics do
  @moduledoc """
  Emits the canonical telemetry event for requests classified using client signals.
  """

  @event [:client_signals, :request]

  @doc """
  Emits one request observation with the bounded metric labels.
  """
  def observe(labels) when is_map(labels) do
    :telemetry.execute(@event, %{count: 1}, labels)
  end
end
