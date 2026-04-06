defmodule KubevirtTools.ClusterVersion do
  @moduledoc false

  @kubevirt_api "kubevirt.io/v1"

  @doc """
  Returns `gitVersion` from `GET /version` (same as `kubectl version --short`).
  """
  @spec kubernetes_git_version(K8s.Conn.t()) :: {:ok, String.t()} | {:error, term()}
  def kubernetes_git_version(%K8s.Conn{} = conn) do
    with {:ok, request_options} <- K8s.Conn.RequestOptions.generate(conn),
         uri <- version_uri(conn),
         headers <- K8s.Client.Provider.headers(request_options),
         opts <- [ssl: request_options.ssl_options],
         {:ok, body} <- conn.http_provider.request(:get, uri, nil, headers, opts),
         true <- is_map(body) do
      v =
        Map.get(body, "gitVersion") ||
          Map.get(body, "version") ||
          "—"

      {:ok, to_string(v)}
    else
      false -> {:error, :unexpected_version_body}
      {:error, _} = err -> err
    end
  end

  defp version_uri(conn) do
    ((conn.url |> String.trim_trailing("/")) <> "/version") |> URI.parse()
  end

  @doc """
  Best-effort KubeVirt operator version from the first `KubeVirt` CR
  (`status.observedKubeVirtVersion`, then `status.targetKubeVirtVersion`).

  Returns `{:ok, "Not installed"}` when the API is available but no CR exists.
  """
  @spec kubevirt_release_version(K8s.Conn.t()) :: {:ok, String.t()} | {:error, term()}
  def kubevirt_release_version(%K8s.Conn{} = conn) do
    op = K8s.Client.list(@kubevirt_api, "KubeVirt", namespace: :all)

    case K8s.Client.run(conn, op) do
      {:ok, %{"items" => []}} ->
        {:ok, "Not installed"}

      {:ok, %{"items" => items}} when is_list(items) ->
        labels =
          items
          |> Enum.map(&kubevirt_version_from_cr/1)
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.uniq()

        {:ok, if(labels == [], do: "—", else: Enum.join(labels, ", "))}

      {:ok, _} ->
        {:ok, "—"}

      {:error, _} = err ->
        err
    end
  end

  defp kubevirt_version_from_cr(cr) when is_map(cr) do
    get_in(cr, ["status", "observedKubeVirtVersion"]) ||
      get_in(cr, ["status", "targetKubeVirtVersion"])
  end
end
