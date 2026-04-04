defmodule KubevirtTools.VmExport.Bundle do
  @moduledoc false

  alias KubevirtTools.ClusterExportLists
  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.KubeVirt
  alias KubevirtTools

  @await_timeout 120_000

  @doc """
  Loads all cluster lists needed for the multi-sheet export workbook (best-effort;
  missing APIs yield empty lists).
  """
  @spec fetch(K8s.Conn.t()) :: {:ok, map()}
  def fetch(%K8s.Conn{} = conn) do
    tasks = %{
      vms: async(&KubeVirt.list_virtual_machines/1, conn),
      vmis: async(&KubeVirt.list_virtual_machine_instances/1, conn),
      nodes: async(&ClusterInventory.list_nodes/1, conn),
      pvcs: async(&ClusterInventory.list_pvcs/1, conn),
      storage_classes: async(&ClusterExportLists.list_storage_classes/1, conn),
      resource_quotas: async(&ClusterExportLists.list_resource_quotas/1, conn),
      limit_ranges: async(&ClusterExportLists.list_limit_ranges/1, conn),
      events: async(&ClusterExportLists.list_events/1, conn),
      vm_snapshots: async(&ClusterExportLists.list_virtual_machine_snapshots/1, conn),
      vm_migrations: async(&ClusterExportLists.list_virtual_machine_instance_migrations/1, conn),
      data_volumes: async(&ClusterExportLists.list_data_volumes/1, conn),
      vm_preferences: async(&ClusterExportLists.list_vm_cluster_preferences/1, conn)
    }

    resolved =
      Map.new(tasks, fn {k, t} ->
        {k, await(t)}
      end)

    meta = %{
      cluster_name: conn.cluster_name || "",
      user_name: conn.user_name || "",
      api_url: conn.url || "",
      app_version: KubevirtTools.version_string()
    }

    {:ok, Map.merge(resolved, %{meta: meta, generated_at: DateTime.utc_now()})}
  end

  defp async(fun, conn), do: Task.async(fn -> grab(fun, conn) end)

  defp await(task), do: Task.await(task, @await_timeout)

  defp grab(fun, conn) do
    case fun.(conn) do
      {:ok, items} when is_list(items) -> items
      _ -> []
    end
  end
end
