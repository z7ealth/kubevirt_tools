defmodule KubevirtTools.ClusterMetrics do
  @moduledoc """
  Cluster usage from [metrics.k8s.io NodeMetrics](https://github.com/kubernetes/metrics/tree/master/metrics#readme)
  (typically exposed when metrics-server is installed; Prometheus stacks often include it). Storage combines
  ephemeral usage when present with PVC requests as fallback.
  """

  @spec list_node_metrics(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_node_metrics(conn) do
    case do_list_metrics(conn, "metrics.k8s.io/v1beta1") do
      {:ok, _} = ok ->
        ok

      err_v1b ->
        if metrics_version_missing?(err_v1b) do
          do_list_metrics(conn, "metrics.k8s.io/v1")
        else
          err_v1b
        end
    end
  end

  defp do_list_metrics(conn, api_version) do
    op = K8s.Client.list(api_version, "NodeMetrics")

    case K8s.Client.run(conn, op) do
      {:ok, %{"items" => items}} when is_list(items) ->
        {:ok, items}

      {:ok, body} when is_map(body) ->
        {:ok, Map.get(body, "items", [])}

      {:error, _} = err ->
        err
    end
  end

  defp metrics_version_missing?({:error, %K8s.Client.APIError{reason: "NotFound"}}), do: true

  defp metrics_version_missing?({:error, %K8s.Client.APIError{message: msg}})
       when is_binary(msg) do
    m = String.downcase(msg)
    String.contains?(m, "not found") or String.contains?(msg, "404")
  end

  defp metrics_version_missing?(_), do: false

  @doc """
  Builds cluster-wide usage fields: CPU %, memory %, and storage % (PVC / ephemeral fallback).
  """
  def usage_summary(nodes, node_metrics_items, pvcs)
      when is_list(nodes) and is_list(node_metrics_items) and is_list(pvcs) do
    by_name = Map.new(node_metrics_items, fn m -> {node_name(m), m} end)

    cpu = cpu_usage_pct(nodes, by_name)
    mem = memory_usage_pct(nodes, by_name)
    storage = storage_usage(nodes, by_name, pvcs)

    %{cpu: cpu, memory: mem, storage: storage}
  end

  defp node_name(resource) do
    md = Map.get(resource, "metadata") || Map.get(resource, :metadata) || %{}
    Map.get(md, "name") || Map.get(md, :name) || ""
  end

  defp cpu_usage_pct(nodes, metrics_by_name) do
    pairs =
      Enum.reduce(nodes, [], fn n, acc ->
        name = node_name(n)

        if name == "" or not Map.has_key?(metrics_by_name, name) do
          acc
        else
          m = metrics_by_name[name]
          alloc = node_allocatable(n, "cpu")
          use = metric_usage(m, "cpu")

          with a when is_binary(a) <- alloc,
               u when is_binary(u) <- use,
               true <- a != "" and u != "" do
            [{cpu_to_millicores(u), cpu_to_millicores(a)} | acc]
          else
            _ -> acc
          end
        end
      end)

    case pairs do
      [] ->
        hint =
          if map_size(metrics_by_name) > 0 do
            "CPU: could not match nodes to metrics"
          else
            "Setup Prometheus (CPU)"
          end

        {:unavailable, "—", hint}

      _ ->
        {used, cap} =
          Enum.reduce(pairs, {0, 0}, fn {u, c}, {su, sc} -> {su + u, sc + c} end)

        if cap > 0 do
          pct = min(100, round(used * 100 / cap))
          {:ok, "#{pct}%", "of allocatable CPU"}
        else
          {:unavailable, "—", "no allocatable CPU"}
        end
    end
  end

  defp memory_usage_pct(nodes, metrics_by_name) do
    pairs =
      Enum.reduce(nodes, [], fn n, acc ->
        name = node_name(n)

        if name == "" or not Map.has_key?(metrics_by_name, name) do
          acc
        else
          m = metrics_by_name[name]
          alloc = node_allocatable(n, "memory")
          use = metric_usage(m, "memory")

          with a when is_binary(a) <- alloc,
               u when is_binary(u) <- use,
               true <- a != "" and u != "" do
            [{quantity_to_bytes(u), quantity_to_bytes(a)} | acc]
          else
            _ -> acc
          end
        end
      end)

    case pairs do
      [] ->
        hint =
          if map_size(metrics_by_name) > 0 do
            "Memory: could not match nodes to metrics"
          else
            "Setup Prometheus (memory)"
          end

        {:unavailable, "—", hint}

      _ ->
        {used, cap} =
          Enum.reduce(pairs, {0, 0}, fn {u, c}, {su, sc} -> {su + u, sc + c} end)

        if cap > 0 do
          pct = min(100, round(used * 100 / cap))
          {:ok, "#{pct}%", "of allocatable RAM"}
        else
          {:unavailable, "—", "no allocatable memory"}
        end
    end
  end

  defp storage_usage(nodes, metrics_by_name, pvcs) do
    alloc_eph =
      nodes
      |> Enum.map(&node_allocatable(&1, "ephemeral-storage"))
      |> Enum.filter(&is_binary/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&quantity_to_bytes/1)
      |> Enum.sum()

    usage_eph =
      Enum.reduce(nodes, 0, fn n, acc ->
        name = node_name(n)

        if name == "" or not Map.has_key?(metrics_by_name, name) do
          acc
        else
          m = metrics_by_name[name]

          case metric_usage(m, "ephemeral-storage") do
            s when is_binary(s) and s != "" -> acc + quantity_to_bytes(s)
            _ -> acc
          end
        end
      end)

    pvc_bytes = pvc_requests_total_bytes(pvcs)

    cond do
      usage_eph > 0 and alloc_eph > 0 ->
        pct = min(100, round(usage_eph * 100 / alloc_eph))
        {:ok, "#{pct}%", "ephemeral disk (nodes)"}

      alloc_eph > 0 and pvc_bytes > 0 ->
        pct = min(100, round(pvc_bytes * 100 / alloc_eph))
        {:ok, "#{pct}%", "PVC requested / alloc. ephemeral"}

      alloc_eph > 0 and pvc_bytes == 0 ->
        {:ok, "0%", "PVC requested / alloc. ephemeral"}

      pvc_bytes > 0 ->
        {:ok, format_gib(pvc_bytes), "PVC capacity requested"}

      true ->
        {:unavailable, "—", "no ephemeral or PVC data"}
    end
  end

  defp pvc_requests_total_bytes(pvcs) do
    pvcs
    |> Enum.map(&get_in(&1, ["spec", "resources", "requests", "storage"]))
    |> Enum.map(&coerce_quantity/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&quantity_to_bytes/1)
    |> Enum.sum()
  end

  defp node_status(node) do
    Map.get(node, "status") || Map.get(node, :status) || %{}
  end

  defp node_allocatable(node, key) when is_binary(key) do
    alloc =
      Map.get(node_status(node), "allocatable") || Map.get(node_status(node), :allocatable) || %{}

    raw =
      Map.get(alloc, key) ||
        case key do
          "cpu" -> Map.get(alloc, :cpu)
          "memory" -> Map.get(alloc, :memory)
          _ -> nil
        end

    coerce_quantity(raw)
  end

  defp metric_usage(metric, key) when is_binary(key) do
    usage = Map.get(metric, "usage") || Map.get(metric, :usage) || %{}

    raw =
      Map.get(usage, key) ||
        case key do
          "cpu" -> Map.get(usage, :cpu)
          "memory" -> Map.get(usage, :memory)
          _ -> nil
        end

    coerce_quantity(raw)
  end

  defp coerce_quantity(v) when is_binary(v) do
    s = String.trim(v)
    if s == "", do: nil, else: s
  end

  defp coerce_quantity(v) when is_integer(v), do: Integer.to_string(v)

  defp coerce_quantity(v) when is_float(v),
    do: :erlang.float_to_binary(v, [:compact, decimals: 3])

  defp coerce_quantity(_), do: nil

  defp quantity_to_bytes(n) when is_integer(n) and n >= 0, do: n

  defp quantity_to_bytes(s) when is_binary(s) do
    s = String.trim(s)

    cond do
      s == "" ->
        0

      Regex.match?(~r/^[0-9]+$/, s) ->
        String.to_integer(s)

      true ->
        case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]*)$/i, s) do
          [_, num_str, suf] ->
            case Float.parse(num_str) do
              {n, _} -> round(n * storage_suffix_multiplier(suf))
              :error -> 0
            end

          _ ->
            0
        end
    end
  end

  defp quantity_to_bytes(_), do: 0

  defp format_gib(bytes) when bytes >= 0 do
    gib = bytes / (1024 * 1024 * 1024)

    if gib >= 100 do
      "#{Float.round(gib, 0) |> trunc()} GiB"
    else
      "#{Float.round(gib, 1)} GiB"
    end
  end

  # Usage tiles: primary < 80%, warning 80–91%, danger >= 92%.
  @doc false
  def highlight_for_usage({:ok, value, _sub}) when is_binary(value) do
    if String.ends_with?(value, "%") do
      case Integer.parse(String.trim_trailing(value, "%")) do
        {p, _} when p >= 92 -> :danger
        {p, _} when p >= 80 -> :warning
        _ -> :primary
      end
    else
      :neutral
    end
  end

  def highlight_for_usage(_), do: :neutral

  defp cpu_to_millicores(s) when is_binary(s) do
    s = String.trim(s)

    cond do
      String.ends_with?(s, "n") ->
        # nanocores
        case Integer.parse(String.trim_trailing(s, "n")) do
          {n, _} -> max(0, div(n + 999_999, 1_000_000))
          :error -> 0
        end

      String.ends_with?(s, "m") ->
        case Integer.parse(String.trim_trailing(s, "m")) do
          {n, _} -> n
          :error -> 0
        end

      true ->
        case Float.parse(s) do
          {f, _} -> round(f * 1000)
          :error -> cpu_int_cores(s)
        end
    end
  end

  defp cpu_to_millicores(_), do: 0

  defp cpu_int_cores(s) do
    case Integer.parse(s) do
      {n, _} -> n * 1000
      :error -> 0
    end
  end

  defp storage_suffix_multiplier(suf) do
    case String.trim(suf) do
      "" -> 1
      "Ki" -> 1024
      "Mi" -> 1024 ** 2
      "Gi" -> 1024 ** 3
      "Ti" -> 1024 ** 4
      "Pi" -> 1024 ** 5
      "Ei" -> 1024 ** 6
      "K" -> 1000
      "M" -> 1_000_000
      "G" -> 1_000_000_000
      "T" -> 1_000_000_000_000
      _ -> 1
    end
  end
end
