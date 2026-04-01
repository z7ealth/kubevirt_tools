defmodule KubevirtTools.KubeVirt do
  @moduledoc "Lists KubeVirt custom resources via the Kubernetes API ([k8s](https://hex.pm/packages/k8s))."

  @api "kubevirt.io/v1"

  @doc """
  Lists VirtualMachine resources cluster-wide (`namespace: :all`).
  Returns `{:ok, items}` or `{:error, reason}` if the API group is unavailable (e.g. KubeVirt not installed).
  """
  @spec list_virtual_machines(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_virtual_machines(conn) do
    op = K8s.Client.list(@api, "VirtualMachine", namespace: :all)
    normalize_list(K8s.Client.run(conn, op))
  end

  @doc """
  Lists VirtualMachineInstance resources cluster-wide.
  """
  @spec list_virtual_machine_instances(K8s.Conn.t()) :: {:ok, list(map())} | {:error, term()}
  def list_virtual_machine_instances(conn) do
    op = K8s.Client.list(@api, "VirtualMachineInstance", namespace: :all)
    normalize_list(K8s.Client.run(conn, op))
  end

  defp normalize_list({:ok, %{"items" => items}}) when is_list(items), do: {:ok, items}
  defp normalize_list({:ok, body}) when is_map(body), do: {:ok, Map.get(body, "items", [])}
  defp normalize_list({:error, _} = err), do: err
end
