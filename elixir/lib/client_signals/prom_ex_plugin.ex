if Code.ensure_loaded?(PromEx.Plugin) do
  defmodule ClientSignals.PromExPlugin do
    @moduledoc """
    PromEx plugin for the canonical client-signals request counter.
    """

    use PromEx.Plugin

    @impl true
    def event_metrics(_opts) do
      Event.build(
        :fly_client_signals_request_event_metrics,
        [
          counter(
            [:fly, :client_signals, :requests, :total],
            event_name: [:client_signals, :request],
            measurement: :count,
            description: "Requests classified by coarse client signals",
            tags: [:service, :route, :operator, :agent]
          )
        ]
      )
    end
  end
end
