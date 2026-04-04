defmodule KubevirtTools.ExportFilename do
  @moduledoc false

  @doc """
  Filename stem (no extension): `kubevirt_tools_<cluster_name>_YYYYMMDD_HHMMSS` (UTC).
  """
  def stem(cluster_name, at \\ DateTime.utc_now())

  def stem(cluster_name, %DateTime{} = at) do
    name =
      cond do
        is_binary(cluster_name) -> cluster_name
        cluster_name == nil -> ""
        true -> to_string(cluster_name)
      end

    utc =
      case DateTime.shift_zone(at, "Etc/UTC") do
        {:ok, t} -> t
        {:error, _} -> at
      end

    dt = Calendar.strftime(utc, "%Y%m%d_%H%M%S")
    seg = sanitize_filename_segment(name)
    "kubevirt_tools_#{seg}_#{dt}"
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
