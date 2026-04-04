defmodule KubevirtTools.PrometheusMetricsServer do
  @moduledoc """
  Polls the configured Prometheus HTTP API on an interval and broadcasts on PubSub topic
  `prometheus:metrics`. LiveViews subscribe to refresh Prometheus-driven tiles and charts
  without reloading the full Kubernetes snapshot.

  Timers are tracked so `poll_now/0` can run an immediate fetch (e.g. after Prometheus
  starts) without overlapping with the regular interval.
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

  @doc """
  Fetches Prometheus immediately, broadcasts like a normal poll, and resets the interval timer.

  Use when operators start Prometheus after the app, instead of waiting for the next tick.
  """
  def poll_now do
    GenServer.call(__MODULE__, :poll_now, 35_000)
  end

  @impl true
  def init(_opts) do
    state = %{last: nil, timer_ref: nil}
    {:ok, schedule_next_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, state) do
    state = cancel_timer(state)
    last = poll_and_broadcast()
    state = %{state | last: last}
    {:noreply, schedule_next_poll(state, poll_interval_ms())}
  end

  @impl true
  def handle_call(:latest, _from, state) do
    {:reply, state.last, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    state = cancel_timer(state)
    last = poll_and_broadcast()
    state = %{state | last: last}
    state = schedule_next_poll(state, poll_interval_ms())
    {:reply, last, state}
  end

  defp poll_and_broadcast do
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
  end

  defp cancel_timer(%{timer_ref: nil} = state), do: state

  defp cancel_timer(%{timer_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | timer_ref: nil}
  end

  defp schedule_next_poll(state, ms) when is_integer(ms) do
    state = cancel_timer(state)
    ref = Process.send_after(self(), :poll, ms)
    %{state | timer_ref: ref}
  end

  defp poll_interval_ms do
    Application.get_env(:kubevirt_tools, :prometheus_poll_interval_ms, 300_000)
  end
end
