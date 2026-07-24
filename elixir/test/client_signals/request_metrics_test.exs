defmodule ClientSignals.RequestMetricsTest do
  use ExUnit.Case, async: true

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:telemetry)
    :ok
  end

  test "emits the canonical request telemetry event" do
    handler_id = {__MODULE__, self()}

    :telemetry.attach(
      handler_id,
      [:client_signals, :request],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    labels = %{
      service: "sprites-api",
      route: "POST /v1/sprites",
      operator: "agent",
      agent: "codex"
    }

    ClientSignals.RequestMetrics.observe(labels)

    assert_receive {
      [:client_signals, :request],
      %{count: 1},
      ^labels
    }
  end

  test "defines the canonical Prometheus counter and bounded labels" do
    %{metrics: [metric]} = ClientSignals.PromExPlugin.event_metrics([])

    assert metric.name == [:fly, :client_signals, :requests, :total]
    assert metric.tags == [:service, :route, :operator, :agent]
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {event, measurements, metadata})
  end
end
