defmodule KubevirtTools.PrometheusMetricsServer do
  @moduledoc """
  Polls the configured Prometheus HTTP API on an interval and broadcasts on PubSub topic
  `prometheus:metrics`. LiveViews subscribe to refresh Prometheus-driven tiles and charts
  without reloading the full Kubernetes snapshot.

  Full snapshots run every `:prometheus_poll_interval_ms` (heavy: PromQL + node detail).
  After a successful snapshot, lightweight `/-/healthy` checks run every
  `:prometheus_health_interval_ms` so the dashboard can drop "Connected" quickly if Prometheus
  stops responding.

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
    state = %{last: nil, poll_timer_ref: nil, health_timer_ref: nil}
    {:ok, schedule_poll(state, 0)}
  end

  @impl true
  def handle_info(:poll, state) do
    state = cancel_poll_timer(state)
    state = cancel_health_timer(state)
    last = poll_and_broadcast()
    state = %{state | last: last}
    state = schedule_poll(state, poll_interval_ms())
    state = maybe_schedule_health_after_full_ok(state, last)
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    state = cancel_health_timer(state)

    case KubevirtTools.PrometheusClient.health_ping() do
      :ok ->
        state =
          if match?({:ok, _}, state.last) do
            schedule_health(state, health_interval_ms())
          else
            state
          end

        {:noreply, state}

      {:error, reason} ->
        msg = {:error, reason}
        Phoenix.PubSub.broadcast(KubevirtTools.PubSub, @topic, {:prometheus_metrics, msg})
        {:noreply, %{state | last: msg}}
    end
  end

  @impl true
  def handle_call(:latest, _from, state) do
    {:reply, state.last, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    state = cancel_poll_timer(state)
    state = cancel_health_timer(state)
    last = poll_and_broadcast()
    state = %{state | last: last}
    state = schedule_poll(state, poll_interval_ms())
    state = maybe_schedule_health_after_full_ok(state, last)
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

  defp maybe_schedule_health_after_full_ok(state, {:ok, _}),
    do: schedule_health(state, health_interval_ms())

  defp maybe_schedule_health_after_full_ok(state, _), do: state

  defp cancel_poll_timer(%{poll_timer_ref: nil} = state), do: state

  defp cancel_poll_timer(%{poll_timer_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | poll_timer_ref: nil}
  end

  defp cancel_health_timer(%{health_timer_ref: nil} = state), do: state

  defp cancel_health_timer(%{health_timer_ref: ref} = state) do
    _ = Process.cancel_timer(ref)
    %{state | health_timer_ref: nil}
  end

  defp schedule_poll(state, ms) when is_integer(ms) do
    state = cancel_poll_timer(state)
    ref = Process.send_after(self(), :poll, ms)
    %{state | poll_timer_ref: ref}
  end

  defp schedule_health(state, ms) when is_integer(ms) do
    state = cancel_health_timer(state)
    ref = Process.send_after(self(), :health_check, ms)
    %{state | health_timer_ref: ref}
  end

  defp poll_interval_ms do
    Application.get_env(:kubevirt_tools, :prometheus_poll_interval_ms, 300_000)
  end

  defp health_interval_ms do
    Application.get_env(:kubevirt_tools, :prometheus_health_interval_ms, 60_000)
  end
end
