defmodule KubevirtTools.ExportFilename do
  @moduledoc false

  @doc """
  Filename stem (no extension): `current_context_YYYYMMDD_HHMMSS` for the given instant (UTC calendar fields).
  """
  def stem(yaml, at \\ DateTime.utc_now())

  def stem(yaml, %DateTime{} = at) when is_binary(yaml) do
    ctx = current_context_from_kubeconfig(yaml)

    utc =
      case DateTime.shift_zone(at, "Etc/UTC") do
        {:ok, t} -> t
        {:error, _} -> at
      end

    dt = Calendar.strftime(utc, "%Y%m%d_%H%M%S")
    "#{sanitize_filename_segment(ctx)}_#{dt}"
  end

  defp current_context_from_kubeconfig(yaml) do
    case YamlElixir.read_from_string(yaml) do
      {:ok, map} when is_map(map) ->
        case Map.get(map, "current-context") do
          ctx when is_binary(ctx) and ctx != "" -> ctx
          _ -> "unknown-context"
        end

      _ ->
        "unknown-context"
    end
  end

  defp sanitize_filename_segment(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(~r/\s+/, "_")
    |> String.replace(~r/[\/\\:*?"<>|\x00-\x1f]/u, "_")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
    |> then(fn s -> if s == "", do: "cluster", else: s end)
  end
end
