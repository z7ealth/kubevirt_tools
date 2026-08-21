defmodule KubevirtTools.PrometheusClient do
  @moduledoc false

  alias KubevirtTools.PrometheusSetup

  @default_sa_token_path "/var/run/secrets/kubernetes.io/serviceaccount/token"
  @insecure_env_var "PROMETHEUS_INSECURE_SKIP_TLS_VERIFY"

  # Attaches the pod's own in-cluster service-account token (when mounted) as a
  # Bearer credential on every Prometheus request — needed to reach endpoints
  # fronted by an auth proxy, e.g. OpenShift's built-in cluster-monitoring
  # Prometheus (kube-rbac-proxy requires this; grant the SA `cluster-monitoring-view`
  # via deploy/k8s/openshift_monitoring_rolebinding.yaml). Harmless no-op against a
  # Prometheus that doesn't require auth. Only ever sent to the configured
  # PROMETHEUS_URL — treat that as a trusted endpoint.
  defp auth_and_tls_opts do
    headers =
      case bearer_token() do
        nil -> []
        token -> [{"authorization", "Bearer #{token}"}]
      end

    connect_options =
      if insecure_skip_tls_verify?() do
        [transport_opts: [verify: :verify_none]]
      else
        []
      end

    [headers: headers, connect_options: connect_options]
  end

  defp bearer_token do
    path = Application.get_env(:kubevirt_tools, :prometheus_sa_token_path, @default_sa_token_path)

    case File.read(path) do
      {:ok, token} -> String.trim(token)
      _ -> nil
    end
  end

  defp insecure_skip_tls_verify? do
    case System.get_env(@insecure_env_var) do
      nil -> false
      raw -> String.trim(raw) in ["1", "true", "TRUE", "True", "yes", "YES", "on", "ON"]
    end
  end

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
  Minimal HTTP check against Prometheus `/-/healthy` (no PromQL). Used between full snapshots
  to refresh connectivity status without re-querying node metrics.
  """
  @spec health_ping() :: :ok | {:error, String.t()}
  def health_ping do
    base = PrometheusSetup.base_url() |> String.trim_trailing("/")
    timeout = Application.get_env(:kubevirt_tools, :prometheus_client_timeout_ms, 5_000)
    url = base <> "/-/healthy"

    case Req.get(url, Keyword.merge(auth_and_tls_opts(), receive_timeout: timeout)) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "Prometheus health check HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  @doc """
  Range-queries per-VM CPU% and memory% history from standard cAdvisor container
  metrics (`container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`),
  attributed via the VM's virt-launcher pod — the same underlying data source as the
  live used/total values, just Prometheus's stored history instead of a live snapshot.

  Requires Prometheus to be reachable and actually scraping kubelet/cAdvisor (true for
  most Prometheus + Kubernetes setups by default, no KubeVirt-specific exporter needed).

  `vcpu_count` and `mem_total_bytes` are the VM's configured totals (used as the
  percentage denominator, matching `KubevirtTools.VmPresentation.vm_cpu_usage_pct/3`
  and `vm_mem_usage_pct/3`). `start_s`/`end_s` are Unix seconds, `step_s` the
  resolution step in seconds.
  """
  @spec vm_usage_range(
          String.t(),
          String.t(),
          pos_integer(),
          pos_integer(),
          integer(),
          integer(),
          pos_integer()
        ) ::
          {:ok, %{cpu_points: list({integer(), float()}), mem_points: list({integer(), float()})}}
          | {:error, term()}
  def vm_usage_range(pod_namespace, pod_name, vcpu_count, mem_total_bytes, start_s, end_s, step_s) do
    base = PrometheusSetup.base_url() |> String.trim_trailing("/")
    timeout = Application.get_env(:kubevirt_tools, :prometheus_client_timeout_ms, 5_000)

    selector =
      "namespace=\"#{pod_namespace}\", pod=\"#{pod_name}\", container!=\"\", container!=\"POD\""

    cpu_promql =
      "clamp_max(clamp_min(100 * sum(rate(container_cpu_usage_seconds_total{#{selector}}[2m])) / #{max(vcpu_count, 1)}, 0), 100)"

    mem_promql =
      "clamp_max(100 * sum(container_memory_working_set_bytes{#{selector}}) / #{max(mem_total_bytes, 1)}, 100)"

    with {:ok, cpu_points} <- run_range_query(base, cpu_promql, start_s, end_s, step_s, timeout),
         {:ok, mem_points} <- run_range_query(base, mem_promql, start_s, end_s, step_s, timeout) do
      {:ok, %{cpu_points: cpu_points, mem_points: mem_points}}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end

  defp run_range_query(base, promql, start_s, end_s, step_s, timeout) do
    url = base <> "/api/v1/query_range"

    # retry: false — this is queried on every 30s poll, so a slow retry/backoff
    # cycle when Prometheus is unreachable would otherwise stall the caller.
    opts =
      Keyword.merge(auth_and_tls_opts(),
        params: [query: promql, start: start_s, end: end_s, step: step_s],
        receive_timeout: timeout,
        retry: false
      )

    case Req.get(url, opts) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => %{"result" => results}}}} ->
        {:ok, range_points_from_results(results)}

      {:ok, %{status: 200, body: %{"status" => "error", "error" => err}}} ->
        {:error, err}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp range_points_from_results([%{"values" => values} | _]) when is_list(values) do
    for [ts, v] <- values, f = parse_number(v), not is_nil(f) do
      {round(ts * 1000), Float.round(f, 1)}
    end
  end

  defp range_points_from_results(_), do: []

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

    mem_by_instance =
      case query_vector_entries(base, @mem_util_memavailable, timeout) do
        [] -> query_vector_entries(base, @mem_util_memfree, timeout)
        xs -> xs
      end

    %{
      cpu_cluster_pct: cpu_cluster_pct,
      mem_cluster_pct: mem_pct,
      load_buckets: load_buckets,
      cpu_by_instance: cpu_entries,
      mem_by_instance: mem_by_instance
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

    opts =
      Keyword.merge(auth_and_tls_opts(),
        params: [query: query],
        receive_timeout: timeout
      )

    case Req.get(url, opts) do
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
