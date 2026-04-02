defmodule KubevirtTools.ClusterInventory do
  @moduledoc "Additional Kubernetes reads for dashboard metrics (nodes, PVCs)."

  @spec list_nodes(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_nodes(conn) do
    op = K8s.Client.list("v1", "Node")
    normalize_list(K8s.Client.run(conn, op))
  end

  @spec list_pvcs(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_pvcs(conn) do
    op = K8s.Client.list("v1", "PersistentVolumeClaim", namespace: :all)
    normalize_list(K8s.Client.run(conn, op))
  end

  defp normalize_list({:ok, %{"items" => items}}) when is_list(items), do: {:ok, items}
  defp normalize_list({:ok, body}) when is_map(body), do: {:ok, Map.get(body, "items", [])}
  defp normalize_list(other), do: other
end
