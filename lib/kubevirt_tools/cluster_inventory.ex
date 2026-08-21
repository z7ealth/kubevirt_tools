defmodule KubevirtTools.ClusterInventory do
  @moduledoc "Additional Kubernetes reads for dashboard metrics (nodes, PVCs)."

  @spec list_nodes(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_nodes(conn) do
    inspect(conn)
    op = K8s.Client.list("v1", "Node")
    normalize_list(K8s.Client.run(conn, op))
  end

  @spec list_pvcs(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_pvcs(conn) do
    op = K8s.Client.list("v1", "PersistentVolumeClaim", namespace: :all)
    normalize_list(K8s.Client.run(conn, op))
  end

  @doc """
  Lists virt-launcher pods cluster-wide (label `kubevirt.io=virt-launcher`), used to
  attribute per-VM CPU/RAM usage from PodMetrics to the owning VirtualMachine.
  """
  @spec list_virt_launcher_pods(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_virt_launcher_pods(conn) do
    op =
      "v1"
      |> K8s.Client.list("Pod", namespace: :all)
      |> K8s.Operation.put_selector(K8s.Selector.label({"kubevirt.io", "virt-launcher"}))

    normalize_list(K8s.Client.run(conn, op))
  end

  defp normalize_list({:ok, %{"items" => items}}) when is_list(items), do: {:ok, items}
  defp normalize_list({:ok, body}) when is_map(body), do: {:ok, Map.get(body, "items", [])}
  defp normalize_list(other), do: dbg(other)
end
