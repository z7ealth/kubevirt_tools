defmodule KubevirtTools.VmTopology do
  @moduledoc false

  @doc """
  Builds a JSON-friendly graph for the topology view: Kubernetes **Nodes**,
  **VirtualMachines** (linked via matching VMI `status.nodeName`), and optional synthetic
  node vertices for unscheduled VMs or names not present in the Node list.
  """
  @spec build(map()) :: map()
  def build(data) when is_map(data) do
    vms = data[:vms] || data["vms"] || []
    vmis = data[:vmis] || data["vmis"] || []
    nodes_k8s = data[:nodes] || data["nodes"] || []

    vmi_by_key =
      vmis
      |> Enum.map(fn vmi -> {vm_key(vmi), vmi} end)
      |> Map.new()

    cluster_names =
      nodes_k8s
      |> Enum.map(&get_in(&1, ["metadata", "name"]))
      |> Enum.filter(&is_binary/1)

    cluster_set = MapSet.new(cluster_names)

    node_vertices =
      Enum.map(nodes_k8s, fn node ->
        name = get_in(node, ["metadata", "name"])
        ready = node_ready?(node)
        cordoned = node_cordoned?(node)

        scheduling =
          cond do
            not ready -> "not_ready"
            cordoned -> "cordoned"
            true -> "ready"
          end

        %{
          "id" => "node:" <> name,
          "label" => name,
          "group" => "node",
          "nodeScheduling" => scheduling
        }
      end)

    vm_vertices =
      Enum.map(vms, fn vm ->
        key = vm_key(vm)
        vmi = Map.get(vmi_by_key, key)

        node_name =
          case vmi do
            nil ->
              nil

            v ->
              n = vmi_node_name(v)
              if n in [nil, ""], do: nil, else: n
          end

        vm_status = topology_vm_status(vm, vmi)

        %{
          "id" => "vm:" <> key,
          "label" => vm_name(vm),
          "group" => "vm",
          "vmStatus" => vm_status,
          "nodeName" => node_name
        }
      end)

    referenced_node_names =
      vm_vertices
      |> Enum.map(& &1["nodeName"])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    missing_node_names =
      referenced_node_names
      |> MapSet.difference(cluster_set)
      |> Enum.sort()

    orphan_node_vertices =
      Enum.map(missing_node_names, fn name ->
        %{
          "id" => "node:" <> name,
          "label" => name <> " (unknown)",
          "group" => "node",
          "nodeScheduling" => "not_ready"
        }
      end)

    needs_unsched? = Enum.any?(vm_vertices, &is_nil(&1["nodeName"]))

    unsched_vertex =
      if needs_unsched? do
        [
          %{
            "id" => "node:__unscheduled__",
            "label" => "Unscheduled",
            "group" => "node",
            "nodeScheduling" => "unscheduled"
          }
        ]
      else
        []
      end

    node_by_id =
      (node_vertices ++ orphan_node_vertices ++ unsched_vertex)
      |> Enum.map(&{&1["id"], &1})
      |> Map.new()

    graph_nodes = Map.values(node_by_id)

    edges =
      Enum.map(vm_vertices, fn v ->
        nid =
          case v["nodeName"] do
            nil -> "node:__unscheduled__"
            name -> "node:" <> name
          end

        %{"from" => nid, "to" => v["id"]}
      end)

    vm_nodes_only = Enum.map(vm_vertices, &Map.delete(&1, "nodeName"))

    {running, stopped, other} = summary_counts_from_vm_statuses(vm_vertices)

    %{
      "nodes" => graph_nodes ++ vm_nodes_only,
      "edges" => edges,
      "summary" => %{
        "nodes" => length(cluster_names),
        "vms" => length(vms),
        "running" => running,
        "stopped" => stopped,
        "other" => other
      }
    }
  end

  defp vm_key(item) do
    ns = get_in(item, ["metadata", "namespace"]) || "default"
    name = get_in(item, ["metadata", "name"]) || ""
    ns <> "/" <> name
  end

  defp vm_name(item), do: get_in(item, ["metadata", "name"]) || "—"

  # Printable-only phases that mean "still working toward run" — not powered off.
  @transient_printable ~w(
    starting provisioning scheduling migrating pausing paused running
  )

  defp topology_vm_status(vm, vmi) do
    printable = vm_printable_lower(vm)
    vmi_running = vmi_phase_running?(vmi)

    cond do
      vmi_running ->
        "running"

      printable in ["stopped", "stopping", "terminated", "terminating"] ->
        "stopped"

      String.contains?(printable, "stop") ->
        "stopped"

      printable == "running" and not vmi_running ->
        "other"

      errorish_printable?(printable) ->
        "other"

      is_nil(vmi) ->
        if transient_printable?(printable) or String.starts_with?(printable, "wait"),
          do: "other",
          else: "stopped"

      true ->
        topology_vm_status_with_vmi(vmi, printable)
    end
  end

  defp vm_printable_lower(vm) do
    case get_in(vm, ["status", "printableStatus"]) do
      nil ->
        ""

      s ->
        s |> to_string() |> String.trim() |> String.downcase()
    end
  end

  defp vmi_phase_running?(nil), do: false

  defp vmi_phase_running?(vmi) do
    String.downcase(to_string(get_in(vmi, ["status", "phase"]) || "")) == "running"
  end

  defp errorish_printable?(printable) do
    String.contains?(printable, "error") or String.contains?(printable, "fail") or
      String.contains?(printable, "crash")
  end

  defp transient_printable?(printable) do
    printable in @transient_printable or
      String.contains?(printable, "wait") or
      String.contains?(printable, "migrat")
  end

  defp topology_vm_status_with_vmi(vmi, printable) do
    phase = String.downcase(to_string(get_in(vmi, ["status", "phase"]) || ""))

    cond do
      phase in ["pending", "scheduling", "scheduled"] ->
        "other"

      phase in ["failed", "succeeded"] ->
        "stopped"

      printable in ["stopped", "stopping", "terminated", "terminating"] ->
        "stopped"

      String.contains?(printable, "stop") ->
        "stopped"

      true ->
        "other"
    end
  end

  defp summary_counts_from_vm_statuses(vm_vertices) do
    Enum.reduce(vm_vertices, {0, 0, 0}, fn v, {r, s, o} ->
      case v["vmStatus"] do
        "running" -> {r + 1, s, o}
        "stopped" -> {r, s + 1, o}
        _ -> {r, s, o + 1}
      end
    end)
  end

  defp vmi_node_name(item) do
    get_in(item, ["status", "nodeName"])
  end

  defp node_ready?(node) do
    conditions = get_in(node, ["status", "conditions"]) || []

    Enum.any?(conditions, fn c ->
      c["type"] == "Ready" and c["status"] == "True"
    end)
  end

  defp node_cordoned?(node) do
    get_in(node, ["spec", "unschedulable"]) == true
  end
end
