defmodule KubevirtTools.PrometheusClient do
  @moduledoc false

  alias KubevirtTools.PrometheusSetup

  # Per-instance CPU 0–100% from node_exporter-style metrics (idle vs total rates).
  @cpu_util_per_instance """
  100 * (
    1 -
    sum by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
    /
    clamp_min(sum by (instance) (rate(node_cpu_seconds_total[5m])), 0.000001)
  )
  """

  @mem_util_memavailable """
  100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))
  """

  @mem_util_memfree """
  100 * (1 - (node_memory_MemFree_bytes / node_memory_MemTotal_bytes))
  """

  @doc """
  Queries the configured Prometheus HTTP API (`PROMETHEUS_URL`, default `http://localhost:9090`).

  Returns `sum(up)`, optional `prometheus_build_info` version, and **node_detail** when
  `node_exporter` metrics exist (CPU/memory utilization for the dashboard).
  """
  @spec snapshot() :: {:ok, map()} | {:error, String.t()}
  def snapshot do
    base = PrometheusSetup.base_url() |> String.trim_trailing("/")
    timeout = Application.get_env(:kubevirt_tools, :prometheus_client_timeout_ms, 5_000)

    case query_sum_up(base, timeout) do
      {:ok, sum_up} ->
        version = query_prometheus_version(base, timeout)
        node_detail = fetch_node_exporter_metrics(base, timeout)

        {:ok,
         %{
           url: base,
           sum_up: sum_up,
           prometheus_version: version,
           node_detail: node_detail
         }}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  @doc false
  @spec fetch_node_exporter_metrics(String.t(), non_neg_integer()) :: map()
  def fetch_node_exporter_metrics(base, timeout) when is_binary(base) do
    base = String.trim_trailing(base, "/")

    cpu_entries = query_vector_entries(base, @cpu_util_per_instance, timeout)
    cpu_values = Enum.map(cpu_entries, & &1.value)
    cpu_cluster_pct = average(cpu_values)
    load_buckets = bucket_cpu_utilization(cpu_values)

    mem_pct =
      memory_cluster_pct(base, @mem_util_memavailable, timeout) ||
        memory_cluster_pct(base, @mem_util_memfree, timeout)

    %{
      cpu_cluster_pct: cpu_cluster_pct,
      mem_cluster_pct: mem_pct,
      load_buckets: load_buckets,
      cpu_by_instance: cpu_entries
    }
  end

  defp memory_cluster_pct(base, query, timeout)
       when is_binary(base) and is_binary(query) and is_integer(timeout) do
    case query_vector_entries(base, query, timeout) do
      [] ->
        nil

      entries ->
        entries |> Enum.map(& &1.value) |> average()
    end
  end

  defp query_vector_entries(base, query, timeout) do
    case run_instant_query(base, query, timeout) do
      {:ok, %{"data" => %{"result" => results}}} when is_list(results) ->
        for %{"metric" => m, "value" => [_, v]} <- results,
            f = parse_number(v),
            not is_nil(f),
            do: %{label: instance_label(m), value: clamp_pct(f)}

      _ ->
        []
    end
  end

  defp instance_label(%{"instance" => i}) when is_binary(i), do: short_instance(i)
  defp instance_label(_), do: "instance"

  defp short_instance(i) do
    case String.split(i, ":", parts: 2) do
      [host, _] -> host
      _ -> i
    end
  end

  defp average([]), do: nil

  defp average(nums) do
    Enum.sum(nums) / length(nums)
  end

  defp clamp_pct(f) when is_float(f) do
    f |> max(0.0) |> min(100.0)
  end

  defp bucket_cpu_utilization([]), do: [0, 0, 0, 0]

  defp bucket_cpu_utilization(values) do
    Enum.reduce(values, [0, 0, 0, 0], fn v, [b0, b1, b2, b3] ->
      idx =
        cond do
          v < 25 -> 0
          v < 50 -> 1
          v < 75 -> 2
          true -> 3
        end

      List.update_at([b0, b1, b2, b3], idx, &(&1 + 1))
    end)
  end

  defp query_sum_up(base, timeout) do
    case run_instant_query(base, "sum(up)", timeout) do
      {:ok, %{"data" => %{"result" => results}}} when is_list(results) ->
        case results do
          [%{"value" => [_, v]} | _] -> {:ok, parse_number(v)}
          [] -> {:ok, nil}
        end

      {:ok, other} ->
        {:error, {:unexpected, other}}

      {:error, _} = err ->
        err
    end
  end

  defp query_prometheus_version(base, timeout) do
    case run_instant_query(base, "prometheus_build_info", timeout) do
      {:ok, %{"data" => %{"result" => [%{"metric" => m} | _]}}} ->
        Map.get(m, "version")

      _ ->
        nil
    end
  end

  defp run_instant_query(base, query, timeout) do
    url = base <> "/api/v1/query"

    case Req.get(url,
           params: [query: query],
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        case body do
          %{"status" => "success"} = b ->
            {:ok, b}

          %{"status" => "error", "error" => err} when is_binary(err) ->
            {:error, err}

          _ ->
            {:error, :bad_body}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_number(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_number(v) when is_number(v), do: v * 1.0
  defp parse_number(_), do: nil

  defp format_error(reason) when is_binary(reason), do: reason

  defp format_error({:unexpected, body}),
    do: "unexpected Prometheus response: #{inspect(body)}"

  defp format_error(:bad_body), do: "unexpected Prometheus response body"

  defp format_error(%module{} = e) when is_atom(module),
    do: Exception.message(e)

  defp format_error(other), do: inspect(other)
end
