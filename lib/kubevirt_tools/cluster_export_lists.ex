defmodule KubevirtTools.ClusterExportLists do
  @moduledoc false

  @spec list_storage_classes(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_storage_classes(conn) do
    op = K8s.Client.list("storage.k8s.io/v1", "StorageClass")
    normalize(K8s.Client.run(conn, op))
  end

  @spec list_resource_quotas(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_resource_quotas(conn) do
    op = K8s.Client.list("v1", "ResourceQuota", namespace: :all)
    normalize(K8s.Client.run(conn, op))
  end

  @spec list_limit_ranges(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_limit_ranges(conn) do
    op = K8s.Client.list("v1", "LimitRange", namespace: :all)
    normalize(K8s.Client.run(conn, op))
  end

  @spec list_events(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_events(conn) do
    op = K8s.Client.list("events.k8s.io/v1", "Event", namespace: :all)

    case normalize(K8s.Client.run(conn, op)) do
      {:ok, _} = ok ->
        ok

      _ ->
        op2 = K8s.Client.list("v1", "Event", namespace: :all)
        normalize(K8s.Client.run(conn, op2))
    end
  end

  @spec list_virtual_machine_snapshots(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_virtual_machine_snapshots(conn) do
    op =
      K8s.Client.list("snapshot.kubevirt.io/v1beta1", "VirtualMachineSnapshot", namespace: :all)

    case normalize(K8s.Client.run(conn, op)) do
      {:ok, _} = ok ->
        ok

      _ ->
        op2 =
          K8s.Client.list("snapshot.kubevirt.io/v1alpha1", "VirtualMachineSnapshot",
            namespace: :all
          )

        normalize(K8s.Client.run(conn, op2))
    end
  end

  @spec list_virtual_machine_instance_migrations(K8s.Conn.t()) ::
          {:ok, list(map())} | {:error, term()}
  def list_virtual_machine_instance_migrations(conn) do
    op = K8s.Client.list("kubevirt.io/v1", "VirtualMachineInstanceMigration", namespace: :all)
    normalize(K8s.Client.run(conn, op))
  end

  @spec list_data_volumes(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_data_volumes(conn) do
    op = K8s.Client.list("cdi.kubevirt.io/v1beta1", "DataVolume", namespace: :all)
    normalize(K8s.Client.run(conn, op))
  end

  @spec list_vm_cluster_preferences(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_vm_cluster_preferences(conn) do
    op = K8s.Client.list("instancetype.kubevirt.io/v1beta1", "VirtualMachineClusterPreference")

    case normalize(K8s.Client.run(conn, op)) do
      {:ok, _} = ok ->
        ok

      _ ->
        op2 =
          K8s.Client.list("instancetype.kubevirt.io/v1alpha2", "VirtualMachineClusterPreference")

        normalize(K8s.Client.run(conn, op2))
    end
  end

  defp normalize({:ok, %{"items" => items}}) when is_list(items), do: {:ok, items}
  defp normalize({:ok, body}) when is_map(body), do: {:ok, Map.get(body, "items", [])}
  defp normalize(other), do: other
end
