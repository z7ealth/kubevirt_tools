defmodule KubevirtTools.VmPresentation do
  @moduledoc """
  Pure presentation/computation helpers shared by dashboard tables and resource
  show pages: VM/VMI field extraction, network interface and disk row assembly,
  storage class row assembly, and node usage/row assembly.
  """

  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.K8sSafeError
  alias KubevirtTools.VmExport

  def vm_status_counts(vms) do
    Enum.reduce(vms, {0, 0, 0}, fn vm, {r, s, o} ->
      case String.downcase(vm_phase(vm)) do
        "running" -> {r + 1, s, o}
        "stopped" -> {r, s + 1, o}
        _ -> {r, s, o + 1}
      end
    end)
  end

  def vmi_phase_counts(vmis) do
    Enum.reduce(vmis, {0, 0, 0}, fn vmi, {run, not_run, other} ->
      case String.downcase(vmi_phase(vmi)) do
        "running" ->
          {run + 1, not_run, other}

        p when p in ["pending", "scheduling", "failed", "failedhandling"] ->
          {run, not_run + 1, other}

        _ ->
          {run, not_run, other + 1}
      end
    end)
  end

  def guest_cpu_cores_by_vmi_name(vmis) do
    for vmi <- vmis, into: %{} do
      name = vm_meta(vmi, :name)
      cores = vmi_guest_cpu_core_count(vmi)
      {name, cores}
    end
  end

  def vmi_guest_cpu_core_count(vmi) do
    case get_in(vmi, ["spec", "domain", "cpu", "cores"]) do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  def node_resource_rows(nodes, vmis) do
    grouped =
      Enum.group_by(vmis, fn vmi ->
        n = vmi_scheduling_node_name(vmi)
        if n in [nil, "", "—"], do: "Unscheduled", else: n
      end)

    cluster_names =
      nodes
      |> Enum.map(&get_in(&1, ["metadata", "name"]))
      |> Enum.filter(&is_binary/1)
      |> Enum.sort()

    cluster_set = MapSet.new(cluster_names)
    grouped_keys = grouped |> Map.keys() |> MapSet.new()

    orphans =
      grouped_keys
      |> MapSet.difference(cluster_set)
      |> MapSet.delete("Unscheduled")
      |> Enum.sort()

    has_unsched? = match?([_ | _], Map.get(grouped, "Unscheduled", []))

    labels =
      cluster_names ++ orphans ++ if(has_unsched?, do: ["Unscheduled"], else: [])

    cond do
      labels == [] and grouped == %{} ->
        {["—"], [0], [0], [0]}

      labels == [] ->
        fallback_node_rows_from_grouped(grouped)

      true ->
        counts = Enum.map(labels, fn l -> length(Map.get(grouped, l, [])) end)

        guest_cpu_totals =
          Enum.map(labels, fn l ->
            grouped |> Map.get(l, []) |> Enum.map(&vmi_guest_cpu_core_count/1) |> Enum.sum()
          end)

        mems =
          Enum.map(labels, fn l ->
            grouped |> Map.get(l, []) |> Enum.map(&vmi_memory_mib/1) |> Enum.sum()
          end)

        {labels, counts, guest_cpu_totals, mems}
    end
  end

  def fallback_node_rows_from_grouped(grouped) do
    labels = grouped |> Map.keys() |> Enum.sort()

    counts = Enum.map(labels, fn l -> length(Map.get(grouped, l, [])) end)

    guest_cpu_totals =
      Enum.map(labels, fn l ->
        grouped |> Map.get(l, []) |> Enum.map(&vmi_guest_cpu_core_count/1) |> Enum.sum()
      end)

    mems =
      Enum.map(labels, fn l ->
        grouped |> Map.get(l, []) |> Enum.map(&vmi_memory_mib/1) |> Enum.sum()
      end)

    {labels, counts, guest_cpu_totals, mems}
  end

  def vmi_memory_mib(vmi) do
    guest = get_in(vmi, ["spec", "domain", "memory", "guest"]) || ""

    guest
    |> to_string()
    |> String.trim()
    |> parse_memory_to_mib()
  end

  def parse_memory_to_mib(""), do: 0

  def parse_memory_to_mib(s) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)\s*(Ki|Mi|Gi|K|M|G)?$/i, s) do
      [_, num_str, suffix] ->
        case Float.parse(num_str) do
          {n, _} ->
            suf = suffix |> to_string() |> String.downcase()
            mult = if suf == "", do: 1, else: memory_suffix_to_mib_mult(suf)
            round(n * mult)

          :error ->
            0
        end

      _ ->
        0
    end
  end

  def memory_suffix_to_mib_mult("ki"), do: 1 / 1024
  def memory_suffix_to_mib_mult("k"), do: 1 / 1024
  def memory_suffix_to_mib_mult("mi"), do: 1
  def memory_suffix_to_mib_mult("m"), do: 1
  def memory_suffix_to_mib_mult("gi"), do: 1024
  def memory_suffix_to_mib_mult("g"), do: 1024
  def memory_suffix_to_mib_mult(_), do: 1

  def pvc_status_counts(pvcs) do
    Enum.reduce(pvcs, {0, 0, 0, 0}, fn pvc, {b, p, l, o} ->
      phase = get_in(pvc, ["status", "phase"]) |> to_string() |> String.downcase()

      cond do
        phase == "bound" -> {b + 1, p, l, o}
        phase == "pending" -> {b, p + 1, l, o}
        phase == "lost" -> {b, p, l + 1, o}
        true -> {b, p, l, o + 1}
      end
    end)
  end

  def pvc_by_storage_class(pvcs) do
    grouped =
      Enum.group_by(pvcs, fn pvc ->
        get_in(pvc, ["spec", "storageClassName"]) || "default"
      end)

    labels = grouped |> Map.keys() |> Enum.sort()
    series = Enum.map(labels, fn l -> length(Map.get(grouped, l, [])) end)
    {labels, series}
  end

  def pvc_counts_by_storage_class_name(pvcs) when is_list(pvcs) do
    pvcs
    |> Enum.map(fn p ->
      sc = get_in(p, ["spec", "storageClassName"])

      if sc in [nil, ""] do
        ""
      else
        to_string(sc)
      end
    end)
    |> Enum.frequencies()
  end

  def storage_class_name_set(storage_classes) when is_list(storage_classes) do
    MapSet.new(
      for sc <- storage_classes,
          n = get_in(sc, ["metadata", "name"]),
          is_binary(n),
          do: n
    )
  end

  def orphan_storage_class_refs_with_counts(pvc_by_class, sc_names) do
    pvc_by_class
    |> Enum.reject(fn {k, _} -> k == "" end)
    |> Enum.reject(fn {k, _} -> MapSet.member?(sc_names, k) end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  def orphan_storage_class_refs_pretty([]), do: ""

  def orphan_storage_class_refs_pretty(refs) do
    refs
    |> Enum.map(fn {name, n} ->
      if n == 1, do: "#{name} (1 PVC)", else: "#{name} (#{n} PVCs)"
    end)
    |> Enum.join(", ")
  end

  def storage_classes_table_rows(storage_classes, pvc_by_class) when is_list(storage_classes) do
    storage_classes
    |> Enum.sort_by(&get_in(&1, ["metadata", "name"]))
    |> Enum.map(&storage_class_table_row(&1, pvc_by_class))
  end

  def storage_class_table_row(sc, pvc_by_class) do
    name = get_in(sc, ["metadata", "name"]) || "—"
    default? = storage_class_default_annotation?(sc)
    provisioner = get_in(sc, ["provisioner"]) |> format_cell()
    reclaim = format_sc_reclaim(get_in(sc, ["reclaimPolicy"]))
    binding = format_sc_binding(get_in(sc, ["volumeBindingMode"]))
    expand = get_in(sc, ["allowVolumeExpansion"])
    pvc_count = Map.get(pvc_by_class, name, 0)
    {display, full} = storage_class_parameters_display(get_in(sc, ["parameters"]))

    %{
      name: name,
      default?: default?,
      provisioner: provisioner,
      reclaim: reclaim,
      binding: binding,
      expand: expand,
      pvc_count: pvc_count,
      parameters_display: display,
      parameters_full: full
    }
  end

  def storage_class_default_annotation?(sc) do
    case get_in(sc, ["metadata", "annotations", "storageclass.kubernetes.io/is-default-class"]) do
      "true" -> true
      true -> true
      _ -> false
    end
  end

  def format_sc_reclaim(nil), do: "Delete"
  def format_sc_reclaim(""), do: "Delete"
  def format_sc_reclaim(s), do: to_string(s)

  def format_sc_binding(nil), do: "Immediate"
  def format_sc_binding(""), do: "Immediate"
  def format_sc_binding(s), do: to_string(s)

  def storage_class_parameters_display(nil), do: {"—", ""}

  def storage_class_parameters_display(params) when params == %{}, do: {"—", ""}

  def storage_class_parameters_display(params) when is_map(params) do
    full =
      params
      |> Enum.sort_by(fn {k, _} -> to_string(k) end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(", ")

    display =
      if String.length(full) > 80 do
        String.slice(full, 0, 77) <> "..."
      else
        full
      end

    {display, full}
  end

  def storage_class_parameters_display(_), do: {"—", ""}

  def node_ready?(node) do
    conditions = get_in(node, ["status", "conditions"]) || []

    Enum.any?(conditions, fn c ->
      c["type"] == "Ready" and c["status"] == "True"
    end)
  end

  def node_cordoned?(node) do
    get_in(node, ["spec", "unschedulable"]) == true
  end

  def node_scheduling_counts(nodes) do
    Enum.reduce(nodes, {0, 0, 0}, fn node, {sched, cord, down} ->
      ready = node_ready?(node)
      cordoned = node_cordoned?(node)

      cond do
        not ready ->
          {sched, cord, down + 1}

        cordoned ->
          {sched, cord + 1, down}

        true ->
          {sched + 1, cord, down}
      end
    end)
  end

  def vm_error_text(err), do: K8sSafeError.user_facing(err)

  def vm_meta(item, :namespace), do: get_in(item, ["metadata", "namespace"]) || "—"
  def vm_meta(item, :name), do: get_in(item, ["metadata", "name"]) || "—"

  def vm_meta(item, :created) do
    case get_in(item, ["metadata", "creationTimestamp"]) do
      nil -> "—"
      ts -> ts
    end
  end

  def vm_phase(item) do
    get_in(item, ["status", "printableStatus"]) || "—"
  end

  @doc """
  Status tone for a VM's printable status (see `phase_tone/1`).
  """
  def vm_phase_tone(vm), do: phase_tone(vm_phase(vm))

  @doc """
  Status tone for a VM/VMI phase string, rendered by the web layer as a
  status chip: `:ok` running, `:stopped` stopped, `:warning` transitional,
  `:error` failures, `:info` waiting/pending/unknown, `:neutral` otherwise.
  """
  @spec phase_tone(String.t() | nil) :: :ok | :stopped | :warning | :error | :info | :neutral
  def phase_tone(phase) do
    phase = phase |> to_string() |> String.trim() |> String.downcase()

    cond do
      phase in ["", "—"] ->
        :neutral

      phase in ["running", "succeeded"] ->
        :ok

      phase == "stopped" ->
        :stopped

      phase in [
        "starting",
        "stopping",
        "terminating",
        "migrating",
        "provisioning",
        "paused",
        "scheduling",
        "scheduled"
      ] ->
        :warning

      String.contains?(phase, "error") or String.contains?(phase, "failed") or
          String.contains?(phase, "crash") ->
        :error

      String.contains?(phase, "waiting") or String.contains?(phase, "pending") or
          phase == "unknown" ->
        :info

      true ->
        :neutral
    end
  end

  @doc """
  Status tone for a PersistentVolumeClaim phase: `:ok` Bound, `:info`
  Pending, `:error` Lost, `:neutral` otherwise.
  """
  @spec pvc_phase_tone(String.t() | nil) :: :ok | :info | :error | :neutral
  def pvc_phase_tone("Bound"), do: :ok
  def pvc_phase_tone("Pending"), do: :info
  def pvc_phase_tone("Lost"), do: :error
  def pvc_phase_tone(_phase), do: :neutral

  def vmi_phase(item) do
    get_in(item, ["status", "phase"]) || "—"
  end

  def vmi_scheduling_node_name(item) do
    get_in(item, ["status", "nodeName"]) || "—"
  end

  def vmi_index_by_ns_name(vmis) when is_list(vmis) do
    for vmi <- vmis, into: %{} do
      k = {vm_meta(vmi, :namespace), vm_meta(vmi, :name)}
      {k, vmi}
    end
  end

  def vmi_lookup_match(lookup, vm) when is_map(lookup) and is_map(vm) do
    Map.get(lookup, {vm_meta(vm, :namespace), vm_meta(vm, :name)})
  end

  def vmi_orphans_without_vm(vms, vmis) when is_list(vms) and is_list(vmis) do
    keys =
      MapSet.new(
        for vm <- vms do
          {vm_meta(vm, :namespace), vm_meta(vm, :name)}
        end
      )

    Enum.filter(vmis, fn vmi ->
      k = {vm_meta(vmi, :namespace), vm_meta(vmi, :name)}
      not MapSet.member?(keys, k)
    end)
  end

  def virtual_machine_cpu_topology_cells(vm, vmi) do
    vm
    |> virtual_machine_cpu_domain_for_row(vmi)
    |> format_domain_cpu_topology()
  end

  def virtual_machine_cpu_domain_for_row(vm, vmi) do
    vmi_cpu = vmi && get_in(vmi, ["spec", "domain", "cpu"])
    vm_cpu = get_in(vm, ["spec", "template", "spec", "domain", "cpu"])

    if domain_cpu_has_numeric_topology?(vmi_cpu) do
      vmi_cpu
    else
      vm_cpu
    end
  end

  def domain_cpu_has_numeric_topology?(nil), do: false

  def domain_cpu_has_numeric_topology?(cpu) when is_map(cpu) do
    Enum.any?(["cores", "sockets", "threads"], fn k ->
      case cpu[k] do
        nil -> false
        n when is_integer(n) and n >= 1 -> true
        n when is_binary(n) -> match?({i, _} when i >= 1, Integer.parse(String.trim(n)))
        _ -> false
      end
    end)
  end

  def format_domain_cpu_topology(nil), do: {"1", "1", "1"}

  def format_domain_cpu_topology(cpu) when is_map(cpu) do
    cores_n = cpu_topology_int(cpu["cores"])
    socks_n = cpu_topology_int(cpu["sockets"])
    thr_n = cpu_topology_int(cpu["threads"])
    s_eff = socks_n || 1
    c_eff = cores_n || 1
    t_eff = thr_n || 1
    guest_cpu_total = s_eff * c_eff * t_eff

    {
      Integer.to_string(c_eff),
      Integer.to_string(s_eff),
      Integer.to_string(guest_cpu_total)
    }
  end

  def cpu_topology_int(nil), do: nil

  def cpu_topology_int(n) when is_integer(n) and n >= 1, do: n

  def cpu_topology_int(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i >= 1 -> i
      _ -> nil
    end
  end

  def cpu_topology_int(_), do: nil

  def memory_for_vm_row(vm, nil), do: vm_spec_memory_guest(vm)

  def memory_for_vm_row(vm, vmi) do
    case get_in(vmi, ["spec", "domain", "memory", "guest"]) do
      nil -> vm_spec_memory_guest(vm)
      s -> format_cell(s)
    end
  end

  def vm_boot_mode(vm), do: VmExport.boot_mode_label(vm)

  @doc """
  "consumed/total" CPU display for a VM row, e.g. `"340m/2"`. `usage` is the map
  returned by `KubevirtTools.ClusterMetrics.vm_resource_usage/3`. Shows `"—"` for
  the consumed side (not blank) when no virt-launcher pod or PodMetrics could be
  matched — callers should pair this with a tooltip explaining why.
  """
  @spec vm_cpu_usage_display(map(), map() | nil, map()) :: String.t()
  def vm_cpu_usage_display(vm, vmi, usage) do
    {_cores, _sockets, guest_cpu_total} = virtual_machine_cpu_topology_cells(vm, vmi)

    consumed =
      case usage[:cpu_millicores] do
        n when is_integer(n) -> "#{n}m"
        _ -> "—"
      end

    "#{consumed}/#{guest_cpu_total}"
  end

  @doc """
  "consumed/total" memory display for a VM row, e.g. `"890Mi/2Gi"`. Shows `"—"` for
  the consumed side (not blank) when no virt-launcher pod or PodMetrics could be
  matched — callers should pair this with a tooltip explaining why.
  """
  @spec vm_mem_usage_display(map(), map() | nil, map()) :: String.t()
  def vm_mem_usage_display(vm, vmi, usage) do
    total = memory_for_vm_row(vm, vmi)

    consumed =
      case usage[:mem_bytes] do
        n when is_integer(n) -> format_bytes_short(n)
        _ -> "—"
      end

    "#{consumed}/#{total}"
  end

  @doc "True when a VM's resource usage could not be attributed to a pod/metrics."
  @spec vm_usage_unavailable?(map()) :: boolean()
  def vm_usage_unavailable?(usage) do
    is_nil(usage[:cpu_millicores]) or is_nil(usage[:mem_bytes])
  end

  @doc "CPU usage percent (0-100) of the VM's configured vCPUs, or nil when unknown."
  @spec vm_cpu_usage_pct(map(), map() | nil, map()) :: 0..100 | nil
  def vm_cpu_usage_pct(vm, vmi, usage) do
    case usage[:cpu_millicores] do
      n when is_integer(n) ->
        {_cores, _sockets, guest_cpu_total} = virtual_machine_cpu_topology_cells(vm, vmi)
        total_millicores = String.to_integer(guest_cpu_total) * 1000
        if total_millicores > 0, do: min(100, round(n * 100 / total_millicores))

      _ ->
        nil
    end
  end

  @doc "Memory usage percent (0-100) of the VM's configured memory, or nil when unknown."
  @spec vm_mem_usage_pct(map(), map() | nil, map()) :: 0..100 | nil
  def vm_mem_usage_pct(vm, vmi, usage) do
    case usage[:mem_bytes] do
      n when is_integer(n) ->
        total_bytes = vm |> memory_for_vm_row(vmi) |> ClusterMetrics.quantity_to_bytes()
        if total_bytes > 0, do: min(100, round(n * 100 / total_bytes))

      _ ->
        nil
    end
  end

  @doc """
  Status tone for a usage percent, matching the dashboard's stat tiles:
  `:ok` below 50%, `:warning` 50–79%, `:stopped` (soft red) 80% and above,
  `:muted` when unknown.
  """
  @spec usage_pct_tone(0..100 | nil) :: :ok | :warning | :stopped | :muted
  def usage_pct_tone(nil), do: :muted
  def usage_pct_tone(pct) when pct >= 80, do: :stopped
  def usage_pct_tone(pct) when pct >= 50, do: :warning
  def usage_pct_tone(_pct), do: :ok

  @doc """
  Precomputed row data for the VMs table — one map per VM with every display
  field already resolved, matching the same "rows" pattern already used for
  the Networks/Disks/Storage classes/Nodes tables (makes filtering trivial).
  """
  @spec virtual_machines_table_rows(list(map()), list(map()), list(map()), list(map())) ::
          list(map())
  def virtual_machines_table_rows(vms, vmis, virt_launcher_pods, pod_metrics) do
    vmi_lookup = vmi_index_by_ns_name(vmis)

    Enum.map(vms, fn vm ->
      vmi = vmi_lookup_match(vmi_lookup, vm)
      usage = ClusterMetrics.vm_resource_usage(vm, virt_launcher_pods, pod_metrics)

      %{
        vm: vm,
        vmi: vmi,
        namespace: vm_meta(vm, :namespace),
        name: vm_meta(vm, :name),
        phase: vm_phase(vm),
        phase_tone: vm_phase_tone(vm),
        cpu_display: vm_cpu_usage_display(vm, vmi, usage),
        cpu_pct: vm_cpu_usage_pct(vm, vmi, usage),
        mem_display: vm_mem_usage_display(vm, vmi, usage),
        mem_pct: vm_mem_usage_pct(vm, vmi, usage),
        usage_unavailable?: vm_usage_unavailable?(usage),
        node: if(vmi, do: vmi_scheduling_node_name(vmi), else: "—"),
        ip: if(vmi, do: vmi_primary_ip(vmi), else: "—"),
        agent_connected?: vmi_agent_connected?(vmi),
        os: vmi_os_display(vmi),
        created: vm_meta(vm, :created)
      }
    end)
  end

  @doc """
  Guest-reported OS, e.g. "Ubuntu 26.04 LTS" — from the VMI's
  `status.guestOSInfo` (populated by the in-guest qemu-guest-agent, same
  source `vmi_agent_connected?/1` checks). "—" when the VMI is missing, the
  agent hasn't reported yet, or the guest doesn't run one.
  """
  @spec vmi_os_display(map() | nil) :: String.t()
  def vmi_os_display(nil), do: "—"

  def vmi_os_display(vmi) do
    os = get_in(vmi, ["status", "guestOSInfo"]) || %{}

    cond do
      is_binary(os["prettyName"]) and os["prettyName"] != "" -> os["prettyName"]
      is_binary(os["name"]) and os["name"] != "" -> os["name"]
      true -> "—"
    end
  end

  defp format_bytes_short(bytes) when is_integer(bytes) and bytes >= 0 do
    cond do
      bytes >= 1024 * 1024 * 1024 ->
        "#{Float.round(bytes / (1024 * 1024 * 1024), 1)}Gi"

      bytes >= 1024 * 1024 ->
        "#{bytes |> Kernel./(1024 * 1024) |> Float.round(0) |> trunc()}Mi"

      bytes >= 1024 ->
        "#{bytes |> Kernel./(1024) |> Float.round(0) |> trunc()}Ki"

      true ->
        "#{bytes}B"
    end
  end

  def vm_spec_memory_guest(vm) do
    format_cell(get_in(vm, ["spec", "template", "spec", "domain", "memory", "guest"]))
  end

  def vmi_spec_cpu_cores(item) do
    case cpu_topology_int(get_in(item, ["spec", "domain", "cpu", "cores"])) do
      nil -> "1"
      n -> Integer.to_string(n)
    end
  end

  def vmi_spec_memory_guest(item) do
    format_cell(get_in(item, ["spec", "domain", "memory", "guest"]))
  end

  def vmi_primary_ip(item) do
    interfaces = get_in(item, ["status", "interfaces"]) || []

    ip =
      Enum.find_value(interfaces, fn iface ->
        case iface["ipAddress"] do
          s when is_binary(s) and s != "" ->
            s

          _ ->
            case iface["ipAddresses"] do
              [first | _] when is_binary(first) and first != "" -> first
              _ -> nil
            end
        end
      end)

    format_cell(ip)
  end

  def vmi_ready_label(item) do
    conditions = get_in(item, ["status", "conditions"]) || []

    case Enum.find(conditions, &(&1["type"] == "Ready")) do
      %{"status" => "True"} ->
        "Ready"

      %{"status" => "False"} ->
        "Not ready"

      %{"status" => s} when is_binary(s) ->
        s

      _ ->
        "—"
    end
  end

  @doc """
  True when the QEMU guest agent is reporting in on this VMI, via the
  `AgentConnected` status condition (falls back to `status.guestAgentInfo`
  presence for older KubeVirt versions that don't set the condition).
  """
  @spec vmi_agent_connected?(map() | nil) :: boolean()
  def vmi_agent_connected?(nil), do: false

  def vmi_agent_connected?(item) do
    conditions = get_in(item, ["status", "conditions"]) || []

    Enum.any?(conditions, &(&1["type"] == "AgentConnected" and &1["status"] == "True")) or
      is_map(get_in(item, ["status", "guestAgentInfo"]))
  end

  # CD-ROM / floppy are treated as removable; everything else (disk, lun, …) counts.
  def vm_disk_device_removable?(%{} = d) do
    Map.has_key?(d, "cdrom") or Map.has_key?(d, "floppy")
  end

  def vm_non_removable_disks(vm) do
    disks = get_in(vm, ["spec", "template", "spec", "domain", "devices", "disks"]) || []
    Enum.reject(disks, &vm_disk_device_removable?/1)
  end

  def vm_template_volume_by_name(vm) do
    vols = get_in(vm, ["spec", "template", "spec", "volumes"]) || []

    Map.new(vols, fn v ->
      {v["name"], v}
    end)
  end

  def vm_data_volume_template_by_name(vm) do
    tpls = get_in(vm, ["spec", "dataVolumeTemplates"]) || []

    Map.new(tpls, fn t ->
      {get_in(t, ["metadata", "name"]), t}
    end)
  end

  def vm_volume_storage_gib_contribution(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
      when is_map(vol) do
    cond do
      is_binary(get_in(vol, ["dataVolume", "name"])) ->
        dv_name = get_in(vol, ["dataVolume", "name"])

        case Map.get(dvt_by_name, dv_name) do
          nil ->
            0.0

          tpl ->
            get_in(tpl, ["spec", "pvc", "resources", "requests", "storage"])
            |> parse_k8s_quantity_to_gib()
        end

      is_binary(get_in(vol, ["persistentVolumeClaim", "claimName"])) ->
        claim = get_in(vol, ["persistentVolumeClaim", "claimName"])
        ns = pvc_claim_namespace(vol, vm_ns)

        case ns do
          n when is_binary(n) ->
            case Map.get(pvc_by_ns_claim, {n, claim}) do
              qty when is_binary(qty) -> parse_k8s_quantity_to_gib(qty)
              _ -> 0.0
            end

          _ ->
            0.0
        end

      true ->
        vol
        |> get_in([
          "ephemeral",
          "volumeClaimTemplate",
          "spec",
          "resources",
          "requests",
          "storage"
        ])
        |> parse_k8s_quantity_to_gib()
    end
  end

  def pvc_claim_namespace(vol, vm_ns) do
    case get_in(vol, ["persistentVolumeClaim", "namespace"]) do
      ns when is_binary(ns) and ns != "" -> ns
      _ -> if(vm_ns in [nil, "", "—"], do: nil, else: vm_ns)
    end
  end

  def pvc_requests_by_namespace_claim(pvcs) when is_list(pvcs) do
    Enum.reduce(pvcs, %{}, fn p, acc ->
      ns = get_in(p, ["metadata", "namespace"])
      nm = get_in(p, ["metadata", "name"])

      if is_binary(ns) and is_binary(nm) do
        storage =
          get_in(p, ["spec", "resources", "requests", "storage"]) ||
            get_in(p, ["status", "capacity", "storage"])

        Map.put(acc, {ns, nm}, storage)
      else
        acc
      end
    end)
  end

  def vm_non_removable_disk_storage_sum_gib(vm, pvc_by_ns_claim) do
    vol_by_name = vm_template_volume_by_name(vm)
    dvt_by_name = vm_data_volume_template_by_name(vm)
    vm_ns = vm_meta(vm, :namespace)

    vm
    |> vm_non_removable_disks()
    |> Enum.reduce(0.0, fn disk, acc ->
      name = disk["name"]
      vol = if is_binary(name), do: Map.get(vol_by_name, name), else: nil

      gib =
        if vol do
          vm_volume_storage_gib_contribution(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
        else
          0.0
        end

      acc + gib
    end)
  end

  def vm_disk_column(vm, pvc_by_ns_claim) do
    disks = vm_non_removable_disks(vm)
    count = length(disks)
    gib = vm_non_removable_disk_storage_sum_gib(vm, pvc_by_ns_claim)

    cond do
      count == 0 ->
        "—"

      gib > 0 ->
        format_decimal_gb_display(gib_sum_to_decimal_gb(gib)) <> " GB (#{count})"

      true ->
        Integer.to_string(count)
    end
  end

  def vm_disk_column_title(vm, pvc_by_ns_claim) do
    disks = vm_non_removable_disks(vm)
    count = length(disks)
    names = disks |> Enum.map(& &1["name"]) |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(", ")
    gib = vm_non_removable_disk_storage_sum_gib(vm, pvc_by_ns_claim)

    base =
      "#{count} non-removable disk(s)" <>
        if(names != "", do: " (#{names})", else: "")

    if gib > 0 do
      gb = gib_sum_to_decimal_gb(gib)

      base <>
        " · Σ " <>
        format_decimal_gb_display(gb) <>
        " GB (decimal, from DataVolume templates, ephemeral PVC requests, and cluster PVCs matching claims)"
    else
      base <>
        " — no resolvable sizes (check PVC list permissions / claim names)"
    end
  end

  # Convert binary-GiB sum (1024-based quantities) to decimal GB (10^9 bytes) for display.
  def gib_sum_to_decimal_gb(gib) when is_float(gib) and gib >= 0 do
    gib * 1_073_741_824 / 1_000_000_000
  end

  def format_decimal_gb_display(gb) when is_float(gb) do
    rounded = Float.round(gb, 2)

    if rounded == trunc(rounded) * 1.0 do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 2)
    end
  end

  def parse_k8s_quantity_to_gib(q) when q in [nil, ""], do: 0.0

  def parse_k8s_quantity_to_gib(q) when is_binary(q) do
    case Regex.run(~r/^(\d+(?:\.\d+)?)\s*(Ki|Mi|Gi|Ti|K|M|G|T)?$/i, String.trim(q)) do
      [_, num_str, suffix] ->
        case Float.parse(num_str) do
          {n, _} ->
            suf = (suffix || "") |> to_string() |> String.downcase()
            n * k8s_storage_suffix_to_gib_multiplier(suf)

          :error ->
            0.0
        end

      _ ->
        0.0
    end
  end

  def parse_k8s_quantity_to_gib(q), do: parse_k8s_quantity_to_gib(to_string(q))

  def k8s_storage_suffix_to_gib_multiplier(""), do: 0.0
  def k8s_storage_suffix_to_gib_multiplier("gi"), do: 1.0
  def k8s_storage_suffix_to_gib_multiplier("g"), do: 1.0
  def k8s_storage_suffix_to_gib_multiplier("mi"), do: 1.0 / 1024
  def k8s_storage_suffix_to_gib_multiplier("m"), do: 1.0 / 1024
  def k8s_storage_suffix_to_gib_multiplier("ki"), do: 1.0 / 1024 / 1024
  def k8s_storage_suffix_to_gib_multiplier("k"), do: 1.0 / 1024 / 1024
  def k8s_storage_suffix_to_gib_multiplier("ti"), do: 1024.0
  def k8s_storage_suffix_to_gib_multiplier("t"), do: 1024.0
  def k8s_storage_suffix_to_gib_multiplier(_), do: 0.0

  def virtual_machine_network_interface_rows(vms, vmis) when is_list(vms) do
    lookup = vmi_index_by_ns_name(vmis)

    Enum.flat_map(vms, fn vm ->
      vmi = vmi_lookup_match(lookup, vm)

      ifaces =
        get_in(vm, ["spec", "template", "spec", "domain", "devices", "interfaces"]) || []

      status_by_name = vmi_status_interfaces_by_name(vmi)

      Enum.map(ifaces, fn iface ->
        iname = iface["name"] || "—"
        live = Map.get(status_by_name, iname, %{})

        %{
          namespace: vm_meta(vm, :namespace),
          vm_name: vm_meta(vm, :name),
          iface_name: iname,
          model: format_cell(iface["model"]),
          binding: interface_binding_label(iface),
          mac_spec: format_cell(iface["macAddress"]),
          mac_live: format_cell(live["mac"]),
          ips: format_iface_ips_display(live),
          guest_iface: format_cell(live["interfaceName"]),
          vmi_phase: if(vmi, do: vmi_phase(vmi), else: "—")
        }
      end)
    end)
  end

  def vmi_status_interfaces_by_name(nil), do: %{}

  def vmi_status_interfaces_by_name(vmi) do
    ifaces = get_in(vmi, ["status", "interfaces"]) || []
    Map.new(ifaces, fn i -> {i["name"], i} end)
  end

  def interface_binding_label(iface) when is_map(iface) do
    cond do
      Map.has_key?(iface, "bridge") -> "bridge"
      Map.has_key?(iface, "masquerade") -> "masquerade"
      Map.has_key?(iface, "srIov") or Map.has_key?(iface, "sriov") -> "SR-IOV"
      Map.has_key?(iface, "macvtap") -> "macvtap"
      Map.has_key?(iface, "passthrough") -> "passthrough"
      Map.has_key?(iface, "slirp") -> "slirp"
      Map.has_key?(iface, "binding") -> "binding"
      true -> "default"
    end
  end

  def format_iface_ips_display(iface) when is_map(iface) do
    ips = List.wrap(iface["ipAddresses"])
    primary = iface["ipAddress"]

    list =
      if is_binary(primary) and primary != "" do
        [primary | ips]
      else
        ips
      end

    joined =
      list
      |> Enum.filter(&is_binary/1)
      |> Enum.flat_map(&String.split(&1, ",", trim: true))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.join(", ")

    if joined == "", do: "—", else: joined
  end

  def format_iface_ips_display(_), do: "—"

  def virtual_machine_disk_detail_rows(vms, pvcs) when is_list(vms) do
    pvc_by_ns_claim = pvc_requests_by_namespace_claim(pvcs)
    pvc_info = pvc_extended_info_by_ns_claim(pvcs)

    Enum.flat_map(vms, fn vm ->
      vol_by_name = vm_template_volume_by_name(vm)
      dvt_by_name = vm_data_volume_template_by_name(vm)
      vm_ns = vm_meta(vm, :namespace)

      disks =
        get_in(vm, ["spec", "template", "spec", "domain", "devices", "disks"]) || []

      Enum.map(disks, fn d ->
        name = d["name"] || "—"
        vol = if is_binary(name) and name != "—", do: Map.get(vol_by_name, name), else: nil
        {vkind, vref} = volume_kind_and_ref(vol)
        gib = disk_volume_gib(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
        {sc, ph} = pvc_meta_for_disk_volume(vol, vm_ns, pvc_info)

        %{
          namespace: vm_meta(vm, :namespace),
          vm_name: vm_meta(vm, :name),
          disk_name: name,
          device_kind: disk_device_kind(d),
          bus: disk_device_bus(d),
          boot_order: format_cell(d["bootOrder"]),
          removable?: vm_disk_device_removable?(d),
          volume_kind: vkind,
          source: vref,
          size: format_disk_size_display(gib),
          size_gib: gib,
          storage_class: sc,
          pvc_phase: ph,
          serial: disk_device_serial(d),
          cache: disk_device_cache(d)
        }
      end)
    end)
  end

  def pvc_extended_info_by_ns_claim(pvcs) when is_list(pvcs) do
    Enum.reduce(pvcs, %{}, fn p, acc ->
      ns = get_in(p, ["metadata", "namespace"])
      nm = get_in(p, ["metadata", "name"])

      if is_binary(ns) and is_binary(nm) do
        req =
          get_in(p, ["spec", "resources", "requests", "storage"]) ||
            get_in(p, ["status", "capacity", "storage"])

        Map.put(acc, {ns, nm}, %{
          storage_class: get_in(p, ["spec", "storageClassName"]) || "—",
          phase: get_in(p, ["status", "phase"]) || "—",
          request: req
        })
      else
        acc
      end
    end)
  end

  def disk_volume_gib(nil, _, _, _), do: 0.0

  def disk_volume_gib(vol, dvt_by_name, vm_ns, pvc_by_ns_claim) when is_map(vol) do
    vm_volume_storage_gib_contribution(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
  end

  def pvc_meta_for_disk_volume(nil, _, _), do: {"—", "—"}

  def pvc_meta_for_disk_volume(vol, vm_ns, pvc_info) when is_map(vol) do
    key =
      cond do
        is_binary(get_in(vol, ["persistentVolumeClaim", "claimName"])) ->
          claim = get_in(vol, ["persistentVolumeClaim", "claimName"])
          ns = pvc_claim_namespace(vol, vm_ns)
          if is_binary(ns), do: {ns, claim}, else: nil

        is_binary(get_in(vol, ["dataVolume", "name"])) ->
          dv = get_in(vol, ["dataVolume", "name"])
          ns = if vm_ns in [nil, "", "—"], do: nil, else: vm_ns
          if is_binary(ns), do: {ns, dv}, else: nil

        true ->
          nil
      end

    case key do
      {ns, nm} ->
        case Map.get(pvc_info, {ns, nm}) do
          %{storage_class: sc, phase: ph} -> {format_cell(sc), format_cell(ph)}
          _ -> {"—", "—"}
        end

      _ ->
        {"—", "—"}
    end
  end

  def volume_kind_and_ref(nil), do: {"—", "—"}

  def volume_kind_and_ref(vol) when is_map(vol) do
    cond do
      is_binary(get_in(vol, ["persistentVolumeClaim", "claimName"])) ->
        c = get_in(vol, ["persistentVolumeClaim", "claimName"])
        ns = get_in(vol, ["persistentVolumeClaim", "namespace"])

        ref =
          if is_binary(ns) and ns != "",
            do: "#{ns}/#{c}",
            else: format_cell(c)

        {"PVC", ref}

      is_binary(get_in(vol, ["dataVolume", "name"])) ->
        {"DataVolume", format_cell(get_in(vol, ["dataVolume", "name"]))}

      is_map(vol["emptyDisk"]) ->
        {"emptyDisk", format_cell(get_in(vol, ["emptyDisk", "capacity"]))}

      is_map(vol["containerDisk"]) ->
        {"containerDisk", format_cell(get_in(vol, ["containerDisk", "image"]))}

      Map.has_key?(vol, "cloudInitNoCloud") ->
        sn = get_in(vol, ["cloudInitNoCloud", "userDataSecretRef", "name"])
        nd = get_in(vol, ["cloudInitNoCloud", "networkDataSecretRef", "name"])

        ref =
          [sn, nd]
          |> Enum.filter(&is_binary/1)
          |> Enum.uniq()
          |> Enum.join(", ")

        {"cloudInitNoCloud", if(ref == "", do: "—", else: ref)}

      Map.has_key?(vol, "cloudInitConfigDrive") ->
        {"cloudInitConfigDrive", "—"}

      is_map(vol["memory"]) ->
        {"memory", format_cell(get_in(vol, ["memory", "size"]))}

      Map.has_key?(vol, "ephemeral") ->
        {"ephemeral", "—"}

      is_map(vol["secret"]) ->
        {"secret", format_cell(get_in(vol, ["secret", "secretName"]))}

      is_map(vol["configMap"]) ->
        {"configMap", format_cell(get_in(vol, ["configMap", "name"]))}

      Map.has_key?(vol, "serviceAccount") ->
        {"serviceAccount", "—"}

      Map.has_key?(vol, "sysprep") ->
        {"sysprep", "—"}

      Map.has_key?(vol, "downwardAPI") ->
        {"downwardAPI", "—"}

      true ->
        {"other", "—"}
    end
  end

  def disk_device_kind(%{} = d) do
    cond do
      Map.has_key?(d, "disk") -> "disk"
      Map.has_key?(d, "cdrom") -> "cdrom"
      Map.has_key?(d, "lun") -> "lun"
      Map.has_key?(d, "floppy") -> "floppy"
      true -> "—"
    end
  end

  def disk_device_bus(%{} = d) do
    sub = d["disk"] || d["cdrom"] || d["lun"] || d["floppy"] || %{}
    format_cell(sub["bus"])
  end

  def disk_device_serial(%{} = d) do
    sub = d["disk"] || d["cdrom"] || %{}
    format_cell(sub["serial"])
  end

  def disk_device_cache(%{} = d) do
    sub = d["disk"] || d["cdrom"] || %{}
    format_cell(sub["cache"])
  end

  def format_disk_size_display(gib) when is_float(gib) and gib > 0 do
    format_decimal_gb_display(gib_sum_to_decimal_gb(gib)) <> " GB"
  end

  def format_disk_size_display(_), do: "—"

  def nodes_merged_usage_map(nodes, node_metrics, prometheus_node_detail) do
    ms = ClusterMetrics.per_node_usage_pct(List.wrap(nodes), List.wrap(node_metrics))
    prom = prometheus_exporter_pct_by_node(List.wrap(nodes), prometheus_node_detail)

    Enum.reduce(List.wrap(nodes), %{}, fn n, acc ->
      name = get_in(n, ["metadata", "name"]) || ""

      if name == "" do
        acc
      else
        Map.put(acc, name, merge_node_usage(Map.get(ms, name), Map.get(prom, name)))
      end
    end)
  end

  def merge_node_usage(ms_row, prom_row) do
    ms_row = ms_row || %{cpu: "—", mem: "—"}
    prom_row = prom_row || %{cpu: "—", mem: "—"}

    %{
      cpu: coalesce_node_usage_pct(ms_row[:cpu], prom_row[:cpu]),
      mem: coalesce_node_usage_pct(ms_row[:mem], prom_row[:mem])
    }
  end

  def coalesce_node_usage_pct("—", b), do: normalize_usage_pct_display(b)
  def coalesce_node_usage_pct(nil, b), do: normalize_usage_pct_display(b)
  def coalesce_node_usage_pct("", b), do: normalize_usage_pct_display(b)
  def coalesce_node_usage_pct(a, _), do: a

  def normalize_usage_pct_display(nil), do: "—"
  def normalize_usage_pct_display("—"), do: "—"
  def normalize_usage_pct_display(s) when is_binary(s), do: s

  def prometheus_exporter_pct_by_node(_nodes, detail)
      when detail == nil or detail == %{} do
    %{}
  end

  def prometheus_exporter_pct_by_node(nodes, detail) when is_map(detail) do
    cpu_list = prometheus_instance_series(detail, :cpu_by_instance)
    mem_list = prometheus_instance_series(detail, :mem_by_instance)
    cpu_by = prometheus_label_to_pct_map(cpu_list)
    mem_by = prometheus_label_to_pct_map(mem_list)

    Enum.reduce(List.wrap(nodes), %{}, fn n, acc ->
      name = get_in(n, ["metadata", "name"]) || ""

      if name == "" do
        acc
      else
        labels = node_prometheus_match_labels(n)

        Map.put(acc, name, %{
          cpu: first_exporter_label_match(cpu_by, labels),
          mem: first_exporter_label_match(mem_by, labels)
        })
      end
    end)
  end

  def prometheus_instance_series(detail, key) do
    List.wrap(Map.get(detail, key) || Map.get(detail, Atom.to_string(key)))
  end

  def prometheus_label_to_pct_map(entries) do
    Enum.reduce(entries, %{}, fn e, acc ->
      {l, v} = prometheus_entry_label_value(e)

      if is_binary(l) and l != "" and is_float(v) do
        Map.put(acc, l, format_exporter_pct_display(v))
      else
        acc
      end
    end)
  end

  def prometheus_entry_label_value(e) when is_map(e) do
    l = e[:label] || e["label"]
    v = e[:value] || e["value"]
    v = if is_float(v), do: v, else: if(is_number(v), do: v * 1.0, else: nil)
    {l, v}
  end

  def format_exporter_pct_display(f) when is_float(f) do
    "#{min(100, max(0, round(f)))}%"
  end

  def first_exporter_label_match(by_label, candidates) do
    Enum.find_value(candidates, fn c -> Map.get(by_label, c) end) || "—"
  end

  def node_prometheus_match_labels(node) do
    name = get_in(node, ["metadata", "name"]) || ""
    addrs = get_in(node, ["status", "addresses"]) || []

    ips =
      for %{"type" => t, "address" => a} <- addrs,
          t in ["InternalIP", "ExternalIP"],
          is_binary(a),
          String.trim(a) != "",
          do: String.trim(a)

    dns_hostnames =
      for %{"type" => "Hostname", "address" => a} <- addrs,
          is_binary(a),
          String.trim(a) != "",
          do: String.trim(a)

    hostname_match_variants =
      Enum.flat_map(dns_hostnames, fn h ->
        case String.split(h, ".", parts: 2) do
          [short, _] when short != "" -> [h, short]
          _ -> [h]
        end
      end)

    [name | ips ++ hostname_match_variants]
    |> Enum.uniq()
    |> Enum.reject(&(&1 == ""))
  end

  def kubernetes_nodes_table_rows(nodes, vmis, merged_usage) do
    n_list = nodes |> List.wrap() |> Enum.sort_by(&kubernetes_node_sort_key/1, :asc)
    vmi_counts = vmi_count_by_k8s_node(vmis)
    Enum.map(n_list, &kubernetes_node_table_row(&1, vmi_counts, merged_usage))
  end

  def kubernetes_node_sort_key(n), do: get_in(n, ["metadata", "name"]) || ""

  def vmi_count_by_k8s_node(vmis) do
    Enum.reduce(List.wrap(vmis), %{}, fn vmi, acc ->
      case get_in(vmi, ["status", "nodeName"]) do
        n when is_binary(n) and n != "" -> Map.update(acc, n, 1, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  def kubernetes_node_table_row(node, vmi_counts, usage_map) do
    name = get_in(node, ["metadata", "name"]) || "—"
    ni = get_in(node, ["status", "nodeInfo"]) || %{}
    ready = node_ready?(node)
    pct = Map.get(usage_map, name, %{cpu: "—", mem: "—"})

    os = format_cell(ni["operatingSystem"])
    arch = format_cell(ni["architecture"])

    os_arch =
      cond do
        os != "—" and arch != "—" -> "#{os} / #{arch}"
        os != "—" -> os
        arch != "—" -> arch
        true -> "—"
      end

    rt = ni["containerRuntimeVersion"]

    runtime =
      if is_binary(rt) and rt != "" do
        String.slice(rt, 0, 72)
      else
        "—"
      end

    %{
      name: name,
      is_ready: ready,
      scheduling: kubernetes_node_scheduling_label(node),
      scheduling_hint: kubernetes_node_not_ready_hint(node),
      role: kubernetes_node_role_label(node),
      vmi_count: Map.get(vmi_counts, name, 0),
      cpu_pct: pct[:cpu] || "—",
      mem_pct: pct[:mem] || "—",
      internal_ip: node_address(node, "InternalIP"),
      external_ip: node_address(node, "ExternalIP"),
      cpu_alloc: format_cell(get_in(node, ["status", "allocatable", "cpu"])),
      mem_alloc: format_cell(get_in(node, ["status", "allocatable", "memory"])),
      pods_alloc: format_cell(get_in(node, ["status", "allocatable", "pods"])),
      kubelet: format_cell(ni["kubeletVersion"]),
      os_arch: os_arch,
      os_image: node_os_image_display(ni),
      runtime: runtime
    }
  end

  @doc """
  Node OS image, e.g. "Debian GNU/Linux 13 (trixie)" or "Red Hat Enterprise
  Linux CoreOS 415.92.202307260553-0 (Ootpa)" — from `status.nodeInfo.osImage`.
  Much more identifying than `operatingSystem` (always just "linux"); truncated
  since some distros' strings run long.
  """
  @spec node_os_image_display(map()) :: String.t()
  def node_os_image_display(node_info) when is_map(node_info) do
    case node_info["osImage"] do
      s when is_binary(s) and s != "" -> String.slice(s, 0, 60)
      _ -> "—"
    end
  end

  def kubernetes_node_scheduling_label(node) do
    cond do
      not node_ready?(node) -> "Not ready"
      node_cordoned?(node) -> "Cordoned"
      true -> "Schedulable"
    end
  end

  def kubernetes_node_not_ready_hint(node) do
    if node_ready?(node) do
      nil
    else
      conditions = get_in(node, ["status", "conditions"]) || []

      case Enum.find(conditions, &(&1["type"] == "Ready")) do
        %{"message" => m} when is_binary(m) ->
          t = String.trim(m)
          if t != "", do: String.slice(t, 0, 240), else: nil

        %{"reason" => r} when is_binary(r) ->
          r

        _ ->
          nil
      end
    end
  end

  @doc """
  Node role(s), joined when a node carries more than one `node-role.kubernetes.io/*`
  label (e.g. a control-plane node that's also untainted to run workloads shows
  "control-plane, worker") — same convention `kubectl get nodes`'s ROLES column
  uses. Falls back to "worker" when no such label is present at all.
  """
  def kubernetes_node_role_label(node) do
    labels = get_in(node, ["metadata", "labels"]) || %{}

    roles =
      labels
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "node-role.kubernetes.io/"))
      |> Enum.map(&String.replace_prefix(&1, "node-role.kubernetes.io/", ""))
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    case roles do
      [] -> "worker"
      _ -> Enum.join(roles, ", ")
    end
  end

  def node_address(node, type) when is_binary(type) do
    addrs = get_in(node, ["status", "addresses"]) || []

    case Enum.find(addrs, &(&1["type"] == type)) do
      %{"address" => a} when is_binary(a) and a != "" -> a
      _ -> "—"
    end
  end

  def format_cell(nil), do: "—"
  def format_cell(""), do: "—"
  def format_cell(val) when is_boolean(val), do: if(val, do: "true", else: "false")
  def format_cell(val), do: to_string(val)

  @doc """
  Human-readable poll interval for UI hints (e.g. "10s", "90s", "5min") — used
  so displayed refresh-rate text always matches the actual configured interval
  instead of a hardcoded string.
  """
  @spec format_interval_label(pos_integer()) :: String.t()
  def format_interval_label(ms) when is_integer(ms) and ms > 0 and rem(ms, 60_000) == 0 do
    "#{div(ms, 60_000)}min"
  end

  def format_interval_label(ms) when is_integer(ms) and ms > 0 do
    "#{div(ms, 1000)}s"
  end
end
