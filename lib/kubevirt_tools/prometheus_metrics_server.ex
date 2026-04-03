defmodule KubevirtTools.PrometheusMetricsServer do
  @moduledoc """
  Polls the configured Prometheus HTTP API on an interval and broadcasts on PubSub topic
  `prometheus:metrics`. LiveViews subscribe to refresh Prometheus-driven tiles and charts
  without reloading the full Kubernetes snapshot.
  """
  use GenServer

  @topic "prometheus:metrics"

  def topic, do: @topic

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns `{:ok, map()} | {:error, String.t()} | nil` from the last poll (or nil before first poll completes)."
  def get_latest do
    GenServer.call(__MODULE__, :latest, 30_000)
  end

  @impl true
  def init(_opts) do
    schedule_poll(0)
    {:ok, %{last: nil}}
  end

  @impl true
  def handle_info(:poll, state) do
    last =
      case KubevirtTools.PrometheusClient.snapshot() do
        {:ok, snap} ->
          snap = Map.put(snap, :fetched_at, System.system_time(:millisecond))
          msg = {:ok, snap}
          Phoenix.PubSub.broadcast(KubevirtTools.PubSub, @topic, {:prometheus_metrics, msg})
          msg

        {:error, reason} when is_binary(reason) ->
          msg = {:error, reason}
          Phoenix.PubSub.broadcast(KubevirtTools.PubSub, @topic, {:prometheus_metrics, msg})
          msg

        other ->
          msg = {:error, inspect(other)}
          Phoenix.PubSub.broadcast(KubevirtTools.PubSub, @topic, {:prometheus_metrics, msg})
          msg
      end

    schedule_poll(poll_interval_ms())
    {:noreply, %{state | last: last}}
  end

  @impl true
  def handle_call(:latest, _from, state) do
    {:reply, state.last, state}
  end

  defp schedule_poll(ms) when is_integer(ms) do
    Process.send_after(self(), :poll, ms)
  end

  defp poll_interval_ms do
    Application.get_env(:kubevirt_tools, :prometheus_poll_interval_ms, 300_000)
  end
end
