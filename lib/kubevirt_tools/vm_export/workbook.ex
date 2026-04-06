defmodule KubevirtTools.VmExport.Workbook do
  @moduledoc false

  alias KubevirtTools.VmExport

  @virtual_machine_export_headers [
    "VM",
    "Memory limit",
    "Labels",
    "Annotations",
    "UID",
    "Printable status",
    "Instancetype",
    "Notes",
    "DNS name",
    "Cores",
    "Sockets",
    "Total CPUs (guest)",
    "Memory",
    "NICs",
    "Disks",
    "Allocated",
    "Primary IP",
    "Network #1",
    "Node",
    "OS (template)",
    "OS (guest agent)",
    "Created",
    "Started",
    "Uptime",
    "Run strategy",
    "Live migratable",
    "Eviction strategy",
    "Guest agent",
    "Agent version",
    "CPU request",
    "CPU limit",
    "Memory request"
  ]

  @sheet_order [
    {"Summary", :summary_sheet},
    {"Cluster", :cluster_sheet},
    {"VirtualMachines", :virtual_machines_sheet},
    {"Nodes", :nodes_sheet},
    {"Memory", :memory_sheet},
    {"GuestAgent", :guest_agent_sheet},
    {"Snapshots", :snapshots_sheet},
    {"VM conditions", :vm_conditions_sheet},
    {"Disks", :disks_sheet},
    {"Networks", :networks_sheet},
    {"CPU", :cpu_sheet},
    {"StorageClasses", :storage_classes_sheet},
    {"PVCs", :pvcs_sheet},
    {"ResourceQuotas", :resource_quotas_sheet},
    {"LimitRanges", :limit_ranges_sheet},
    {"Events", :events_sheet},
    {"Migrations", :migrations_sheet},
    {"DataVolumes", :data_volumes_sheet},
    {"ClusterPreferences", :cluster_preferences_sheet}
  ]

  @spec build_workbook(map()) :: Elixlsx.Workbook.t()
  def build_workbook(bundle) when is_map(bundle) do
    Enum.reduce(@sheet_order, %Elixlsx.Workbook{}, fn {name, key}, wb ->
      rows = apply(__MODULE__, key, [bundle])
      Elixlsx.Workbook.append_sheet(wb, %Elixlsx.Sheet{name: name, rows: rows})
    end)
  end

  @spec virtual_machine_inventory_rows(map()) :: {list(String.t()), list(list(String.t()))}
  def virtual_machine_inventory_rows(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    idx = vmi_index(vmis)

    rows =
      Enum.map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        virtual_machine_inventory_row(vm, vmi)
      end)

    {@virtual_machine_export_headers, rows}
  end

  def summary_sheet(bundle) do
    meta = Map.get(bundle, :meta, %{})
    nodes = Map.get(bundle, :nodes, [])
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    gen = Map.get(bundle, :generated_at) || DateTime.utc_now()

    {ready, not_ready} = node_ready_counts(nodes)
    total_cpu = sum_node_cpu_cores(nodes)
    total_mem = sum_node_memory_human(nodes)

    running_vmis = Enum.count(vmis, &(get_in(&1, ["status", "phase"]) == "Running"))

    [
      ["KUBEVIRT TOOLS EXPORT SUMMARY", ""],
      ["", ""],
      ["Generated", format_local(gen)],
      ["Cluster", meta.cluster_name],
      ["KubeVirt Tools Version", meta.app_version],
      ["", ""],
      ["COMPUTE", ""],
      ["Total Nodes", to_string(length(nodes))],
      ["Ready Nodes", to_string(ready)],
      ["Not Ready Nodes", to_string(not_ready)],
      ["Total CPUs", "#{total_cpu} cores"],
      ["Total Memory", total_mem],
      ["", ""],
      ["KUBEVIRT", ""],
      ["Total VirtualMachines", to_string(length(vms))],
      ["Running VMIs", to_string(running_vmis)]
    ]
  end

  def cluster_sheet(bundle) do
    meta = Map.get(bundle, :meta, %{})
    nodes = Map.get(bundle, :nodes, [])
    {ready, _} = node_ready_counts(nodes)
    cp = control_plane_count(nodes)
    workers = length(nodes) - cp
    kver = first_node_kubelet_version(nodes)

    [
      ["CLUSTER", ""],
      ["Cluster Name", meta.cluster_name],
      ["API Server", meta.api_url],
      ["Kubernetes Version (node kubelet sample)", kver],
      ["OpenShift Version", ""],
      ["Platform", ""],
      ["KubeVirt Version", ""],
      ["CDI Version", ""],
      ["", ""],
      ["NODES", ""],
      ["Total Nodes", to_string(length(nodes))],
      ["Ready Nodes", to_string(ready)],
      ["Control Plane Nodes", to_string(cp)],
      ["Worker Nodes", to_string(max(workers, 0))],
      ["Total Node CPUs", to_string(sum_node_cpu_cores(nodes))]
    ]
  end

  def virtual_machines_sheet(bundle) do
    {h, r} = virtual_machine_inventory_rows(bundle)
    [h | r]
  end

  def nodes_sheet(bundle) do
    nodes = Map.get(bundle, :nodes, [])
    vmis = Map.get(bundle, :vmis, [])
    by_node = vmis_by_node(vmis)

    hdr = [
      "Node",
      "Status",
      "Roles",
      "CPUs",
      "CPU model",
      "Allocatable CPU",
      "Memory",
      "Allocatable memory",
      "VMI count",
      "Guest CPUs total",
      "Guest memory total",
      "OS",
      "Kernel",
      "Kubelet version",
      "Container runtime",
      "Schedulable",
      "CPU overcommit",
      "Memory overcommit",
      "Boot Time",
      "Uptime",
      "Taints"
    ]

    rows =
      Enum.map(nodes, fn n ->
        name = meta(n, "name")
        vm_list = Map.get(by_node, name, [])
        guest_cpus = Enum.sum(Enum.map(vm_list, &vmi_guest_cpu_count/1))
        guest_mem = Enum.sum(Enum.map(vm_list, &vmi_memory_bytes/1))

        [
          name,
          node_ready_status(n),
          node_roles(n),
          get_in(n, ["status", "capacity", "cpu"]) || "—",
          get_in(n, ["status", "nodeInfo", "architecture"]) || "—",
          get_in(n, ["status", "allocatable", "cpu"]) || "—",
          get_in(n, ["status", "capacity", "memory"]) || "—",
          get_in(n, ["status", "allocatable", "memory"]) || "—",
          to_string(length(vm_list)),
          to_string(guest_cpus),
          format_bytes(guest_mem),
          get_in(n, ["status", "nodeInfo", "osImage"]) || "—",
          get_in(n, ["status", "nodeInfo", "kernelVersion"]) || "—",
          get_in(n, ["status", "nodeInfo", "kubeletVersion"]) || "—",
          get_in(n, ["status", "nodeInfo", "containerRuntimeVersion"]) || "—",
          to_cell(node_schedulable?(n)),
          "—",
          "—",
          get_in(n, ["status", "nodeInfo", "bootID"]) || "—",
          "—",
          format_taints(n)
        ]
      end)

    [hdr | rows]
  end

  def memory_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    nodes = Map.get(bundle, :nodes, [])
    idx = vmi_index(vmis)
    nmap = Map.new(nodes, fn n -> {meta(n, "name"), n} end)

    hdr = [
      "VM",
      "Namespace",
      "Status",
      "Memory",
      "Memory (bytes)",
      "Memory request",
      "Memory limit",
      "Hugepages",
      "Overcommit guaranteed",
      "Node",
      "Node memory",
      "Node allocatable memory"
    ]

    rows =
      Enum.map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        mem = get_in(vm, ["spec", "template", "spec", "domain", "memory", "guest"]) || ""
        node = vmi && (get_in(vmi, ["status", "nodeName"]) || "")
        nn = node && Map.get(nmap, node)

        [
          name,
          ns,
          VmExport.printable_status(vm),
          mem,
          to_string(vmi_memory_bytes(vmi) || mem_bytes_from_quantity(mem)),
          domain_resource_field(vm, "requests", "memory"),
          domain_resource_field(vm, "limits", "memory"),
          hugepages_summary(vm),
          "—",
          node,
          (nn && (get_in(nn, ["status", "capacity", "memory"]) || "—")) || "—",
          (nn && (get_in(nn, ["status", "allocatable", "memory"]) || "—")) || "—"
        ]
      end)

    [hdr | rows]
  end

  def guest_agent_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    idx = vmi_index(vmis)

    hdr = [
      "VM",
      "Namespace",
      "VM Status",
      "Agent Connected",
      "Agent Version",
      "Hostname",
      "OS (Reported)",
      "OS ID",
      "OS Version",
      "Kernel",
      "Timezone",
      "Primary IP",
      "All IPs"
    ]

    rows =
      Enum.map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        ga = (vmi && get_in(vmi, ["status", "guestAgentInfo"])) || %{}

        [
          name,
          ns,
          VmExport.printable_status(vm),
          to_cell(vmi && get_in(vmi, ["status", "guestAgentInfo"]) != nil),
          to_cell(Map.get(ga, "version")),
          to_cell(Map.get(ga, "hostname")),
          to_cell(get_in(ga, ["os", "name"])),
          to_cell(get_in(ga, ["os", "id"])),
          to_cell(get_in(ga, ["os", "version"])),
          to_cell(get_in(ga, ["kernelRelease"])),
          to_cell(get_in(ga, ["timezone"])),
          primary_ip_from_interfaces(vmi),
          all_ips_from_interfaces(vmi)
        ]
      end)

    [hdr | rows]
  end

  def snapshots_sheet(bundle) do
    snaps = Map.get(bundle, :vm_snapshots, [])

    hdr = [
      "VM",
      "Name",
      "Namespace",
      "Description",
      "Date / time",
      "Age (days)",
      "Ready",
      "Status",
      "Size"
    ]

    rows =
      Enum.map(snaps, fn s ->
        ns = meta(s, "namespace")
        name = meta(s, "name")
        vm_ref = get_in(s, ["spec", "source", "name"]) || ""

        [
          vm_ref,
          name,
          ns,
          "",
          get_in(s, ["metadata", "creationTimestamp"]) || "",
          "",
          to_cell(snapshot_ready?(s)),
          snapshot_phase(s),
          ""
        ]
      end)

    [hdr | rows]
  end

  def vm_conditions_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])

    hdr = ["VM", "Namespace", "Message", "Status", "Type"]

    rows =
      Enum.flat_map(vms, fn vm ->
        conds = get_in(vm, ["status", "conditions"]) || []

        Enum.map(conds, fn c ->
          [
            meta(vm, "name"),
            meta(vm, "namespace"),
            to_cell(Map.get(c, "message")),
            to_cell(Map.get(c, "status")),
            to_cell(Map.get(c, "type"))
          ]
        end)
      end)

    [hdr | rows]
  end

  def disks_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    idx = vmi_index(vmis)
    pvc_ns_name = pvc_index_by_key(Map.get(bundle, :pvcs, []))

    hdr = [
      "VM",
      "Namespace",
      "VM Status",
      "Disk",
      "Capacity",
      "Bus",
      "Cache",
      "Storage Class",
      "PVC",
      "PVC Status",
      "Access Mode",
      "Volume Mode",
      "Boot Order",
      "Hotpluggable",
      "Node"
    ]

    rows =
      Enum.flat_map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        disks = get_in(vm, ["spec", "template", "spec", "domain", "devices", "disks"]) || []
        vols = volumes_by_name(vm)

        Enum.map(disks, fn d ->
          dname = Map.get(d, "name") || ""
          vol = Map.get(vols, dname, %{})
          pvc_ref = volume_pvc_name(vol)
          pvc = pvc_ref && Map.get(pvc_ns_name, {ns, pvc_ref})

          [
            name,
            ns,
            VmExport.printable_status(vm),
            dname,
            pvc_capacity(pvc),
            get_in(d, ["disk", "bus"]) || "",
            get_in(d, ["cache"]) || "",
            (pvc && get_in(pvc, ["spec", "storageClassName"])) || "",
            pvc_ref || "",
            (pvc && get_in(pvc, ["status", "phase"])) || "",
            pvc_access_modes(pvc),
            (pvc && get_in(pvc, ["spec", "volumeMode"])) || "",
            to_cell(get_in(d, ["bootOrder"])),
            to_cell(get_in(d, ["disk", "hotpluggable"])),
            (vmi && get_in(vmi, ["status", "nodeName"])) || ""
          ]
        end)
      end)

    [hdr | rows]
  end

  def networks_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    idx = vmi_index(vmis)

    hdr = [
      "VM",
      "Namespace",
      "VM Status",
      "Interface",
      "Network",
      "Type",
      "Model",
      "MAC",
      "IPv4",
      "IPv6",
      "NAD",
      "Node"
    ]

    rows =
      Enum.flat_map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        ifaces = get_in(vm, ["spec", "template", "spec", "domain", "devices", "interfaces"]) || []

        Enum.map(ifaces, fn iface ->
          iname = Map.get(iface, "name") || ""
          st = interface_status(vmi, iname)

          [
            name,
            ns,
            VmExport.printable_status(vm),
            iname,
            interface_network_name(iface),
            interface_type(iface),
            Map.get(iface, "model") || "",
            get_in(st, ["mac"]) || Map.get(iface, "macAddress") || "",
            first_ip(st, "ipAddresses"),
            "",
            get_in(iface, ["multus", "networkName"]) || "",
            (vmi && get_in(vmi, ["status", "nodeName"])) || ""
          ]
        end)
      end)

    [hdr | rows]
  end

  def cpu_sheet(bundle) do
    vms = Map.get(bundle, :vms, [])
    vmis = Map.get(bundle, :vmis, [])
    nodes = Map.get(bundle, :nodes, [])
    idx = vmi_index(vmis)
    nmap = Map.new(nodes, fn n -> {meta(n, "name"), n} end)

    hdr = [
      "VM",
      "Namespace",
      "Status",
      "Sockets",
      "Cores per socket",
      "Threads",
      "Total CPUs (guest)",
      "Model",
      "Dedicated CPU placement",
      "Node",
      "Node CPUs",
      "Node CPU model"
    ]

    rows =
      Enum.map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(idx, {ns, name})
        dom = get_in(vm, ["spec", "template", "spec", "domain", "cpu"]) || %{}
        sockets = Map.get(dom, "sockets")
        cores = Map.get(dom, "cores") || 1
        threads = Map.get(dom, "threads")
        total = domain_guest_cpu_total(dom, vmi)
        node = (vmi && get_in(vmi, ["status", "nodeName"])) || ""
        nn = node && Map.get(nmap, node)

        [
          name,
          ns,
          VmExport.printable_status(vm),
          to_cell(sockets),
          to_cell(cores),
          to_cell(threads),
          to_cell(total),
          Map.get(dom, "model") || "",
          to_cell(Map.get(dom, "dedicatedCpuPlacement")),
          node,
          (nn && (get_in(nn, ["status", "capacity", "cpu"]) || "")) || "",
          get_in(nn || %{}, ["status", "nodeInfo", "architecture"]) || ""
        ]
      end)

    [hdr | rows]
  end

  def storage_classes_sheet(bundle) do
    pvcs = Map.get(bundle, :pvcs, [])
    scs = Map.get(bundle, :storage_classes, [])

    hdr = [
      "Name",
      "Provisioner",
      "Default",
      "Default (CDI)",
      "Reclaim policy",
      "Binding mode",
      "Volume expansion",
      "PVC count",
      "Snapshot count",
      "PVC allocated",
      "Used",
      "Allocatable free",
      "Used %",
      "Description"
    ]

    counts =
      Enum.reduce(pvcs, %{}, fn p, acc ->
        sc = get_in(p, ["spec", "storageClassName"]) || ""
        Map.update(acc, sc, 1, &(&1 + 1))
      end)

    rows =
      Enum.map(scs, fn sc ->
        n = meta(sc, "name")
        cnt = Map.get(counts, n, 0)

        [
          n,
          get_in(sc, ["provisioner"]) || "",
          to_cell(
            get_in(sc, ["metadata", "annotations", "storageclass.kubernetes.io/is-default-class"]) ==
              "true"
          ),
          "",
          get_in(sc, ["reclaimPolicy"]) || "",
          get_in(sc, ["volumeBindingMode"]) || "",
          to_cell(get_in(sc, ["allowVolumeExpansion"])),
          to_string(cnt),
          "",
          "",
          "",
          "",
          "",
          ""
        ]
      end)

    [hdr | rows]
  end

  def pvcs_sheet(bundle) do
    pvcs = Map.get(bundle, :pvcs, [])
    vm_by_pvc = vm_claiming_pvc_index(Map.get(bundle, :vms, []))

    hdr = [
      "Name",
      "Namespace",
      "VM",
      "Type",
      "Capacity",
      "Storage Class",
      "Status",
      "Access Mode",
      "Volume Mode",
      "Created"
    ]

    rows =
      Enum.map(pvcs, fn p ->
        ns = meta(p, "namespace")
        pn = meta(p, "name")
        vm = Map.get(vm_by_pvc, {ns, pn}, "")

        [
          pn,
          ns,
          vm,
          "PVC",
          get_in(p, ["status", "capacity", "storage"]) ||
            get_in(p, ["spec", "resources", "requests", "storage"]) || "",
          get_in(p, ["spec", "storageClassName"]) || "",
          get_in(p, ["status", "phase"]) || "",
          pvc_access_modes(p),
          get_in(p, ["spec", "volumeMode"]) || "",
          get_in(p, ["metadata", "creationTimestamp"]) || ""
        ]
      end)

    [hdr | rows]
  end

  def resource_quotas_sheet(bundle) do
    qs = Map.get(bundle, :resource_quotas, [])

    hdr = ["Name", "Namespace", "Resource", "Hard Limit", "Used", "Usage %", "Created"]

    rows =
      Enum.flat_map(qs, fn q ->
        hard = get_in(q, ["spec", "hard"]) || %{}
        used = get_in(q, ["status", "used"]) || %{}
        name = meta(q, "name")
        ns = meta(q, "namespace")
        created = get_in(q, ["metadata", "creationTimestamp"]) || ""

        if hard == %{} do
          [[name, ns, "", "", "", "", created]]
        else
          Enum.map(hard, fn {res, lim} ->
            u = Map.get(used, res, "")
            pct = usage_pct(lim, u)

            [
              name,
              ns,
              to_string(res),
              to_string(lim),
              to_string(u),
              pct,
              created
            ]
          end)
        end
      end)

    [hdr | rows]
  end

  def limit_ranges_sheet(bundle) do
    lrs = Map.get(bundle, :limit_ranges, [])

    hdr = [
      "Name",
      "Namespace",
      "Type",
      "Resource",
      "Min",
      "Max",
      "Default",
      "Default Request",
      "Created"
    ]

    rows =
      Enum.flat_map(lrs, fn lr ->
        name = meta(lr, "name")
        ns = meta(lr, "namespace")
        created = get_in(lr, ["metadata", "creationTimestamp"]) || ""
        limits = get_in(lr, ["spec", "limits"]) || []

        if limits == [] do
          [[name, ns, "", "", "", "", "", "", created]]
        else
          Enum.flat_map(limits, fn lim ->
            typ = Map.get(lim, "type") || ""
            max_m = Map.get(lim, "max") || %{}
            min_m = Map.get(lim, "min") || %{}
            def_m = Map.get(lim, "default") || %{}
            dr_m = Map.get(lim, "defaultRequest") || %{}

            keys =
              [Map.keys(max_m), Map.keys(min_m), Map.keys(def_m), Map.keys(dr_m)]
              |> List.flatten()
              |> Enum.uniq()

            Enum.map(keys, fn res ->
              [
                name,
                ns,
                typ,
                to_string(res),
                limit_cell(Map.get(min_m, res)),
                limit_cell(Map.get(max_m, res)),
                limit_cell(Map.get(def_m, res)),
                limit_cell(Map.get(dr_m, res)),
                created
              ]
            end)
          end)
        end
      end)

    [hdr | rows]
  end

  defp limit_cell(nil), do: ""
  defp limit_cell(v), do: to_string(v)

  def events_sheet(bundle) do
    evs =
      bundle
      |> Map.get(:events, [])
      |> Enum.sort_by(&event_sort_key/1, :desc)
      |> Enum.take(5000)

    hdr = [
      "Type",
      "Reason",
      "Object Kind",
      "Object Name",
      "Namespace",
      "Message",
      "Count",
      "First Seen",
      "Last Seen",
      "Source"
    ]

    rows =
      Enum.map(evs, fn e ->
        ref = event_ref(e)

        [
          event_type(e),
          get_in(e, ["reason"]) || "",
          get_in(ref, ["kind"]) || "",
          get_in(ref, ["name"]) || "",
          get_in(ref, ["namespace"]) || "",
          event_message(e),
          to_string(event_count(e)),
          event_first(e),
          event_last(e),
          event_source(e)
        ]
      end)

    [hdr | rows]
  end

  def migrations_sheet(bundle) do
    ms = Map.get(bundle, :vm_migrations, [])

    hdr = [
      "Name",
      "VM",
      "Namespace",
      "Status",
      "Phase",
      "Source Node",
      "Target Node",
      "Created",
      "Completed",
      "Duration",
      "Failure Reason"
    ]

    rows =
      Enum.map(ms, fn m ->
        [
          meta(m, "name"),
          get_in(m, ["spec", "vmiName"]) || "",
          meta(m, "namespace"),
          migration_status_label(m),
          get_in(m, ["status", "phase"]) || "",
          get_in(m, ["status", "sourceNode"]) || "",
          get_in(m, ["status", "targetNode"]) || "",
          get_in(m, ["metadata", "creationTimestamp"]) || "",
          get_in(m, ["status", "completedTimestamp"]) || "",
          "",
          get_in(m, ["status", "migrationState", "failedReason"]) || ""
        ]
      end)

    [hdr | rows]
  end

  def data_volumes_sheet(bundle) do
    dvs = Map.get(bundle, :data_volumes, [])

    hdr = [
      "Name",
      "Namespace",
      "Source Type",
      "Source URL",
      "Capacity",
      "Progress",
      "Phase",
      "Storage Class",
      "Created"
    ]

    rows =
      Enum.map(dvs, fn dv ->
        src = get_in(dv, ["spec", "source"]) || %{}
        {stype, surl} = dv_source_summary(src)

        [
          meta(dv, "name"),
          meta(dv, "namespace"),
          stype,
          surl,
          get_in(dv, ["spec", "pvc", "resources", "requests", "storage"]) || "",
          get_in(dv, ["status", "progress"]) || "",
          get_in(dv, ["status", "phase"]) || "",
          get_in(dv, ["spec", "pvc", "storageClassName"]) || "",
          get_in(dv, ["metadata", "creationTimestamp"]) || ""
        ]
      end)

    [hdr | rows]
  end

  def cluster_preferences_sheet(bundle) do
    prefs = Map.get(bundle, :vm_preferences, [])

    hdr = [
      "Name",
      "Namespace",
      "Description",
      "OS",
      "Flavor",
      "Workload",
      "CPUs",
      "Memory",
      "Created"
    ]

    rows =
      Enum.map(prefs, fn p ->
        [
          meta(p, "name"),
          "",
          get_in(p, ["metadata", "annotations", "description"]) || "",
          "",
          "",
          "",
          "",
          "",
          get_in(p, ["metadata", "creationTimestamp"]) || ""
        ]
      end)

    [hdr | rows]
  end

  # --- VirtualMachines sheet row (CSV uses the same columns) ---

  defp virtual_machine_inventory_row(vm, vmi) do
    name = meta(vm, "name")
    dom = get_in(vm, ["spec", "template", "spec", "domain"]) || %{}
    ifaces = get_in(dom, ["devices", "interfaces"]) || []
    disks = get_in(dom, ["devices", "disks"]) || []
    {cores_cell, sockets_cell, total_cell} = virtual_machine_cpu_columns(vm, vmi, dom)

    [
      name,
      domain_resource_field(vm, "limits", "memory"),
      format_label_map(get_in(vm, ["metadata", "labels"]) || %{}),
      format_label_map(get_in(vm, ["metadata", "annotations"]) || %{}),
      meta(vm, "uid"),
      VmExport.printable_status(vm),
      instancetype_ref(vm),
      "",
      dns_name_from_vm(vm, vmi),
      cores_cell,
      sockets_cell,
      total_cell,
      to_cell(get_in(dom, ["memory", "guest"])),
      to_string(length(ifaces)),
      to_string(length(disks)),
      "",
      primary_ip_from_interfaces(vmi),
      first_network_name(ifaces),
      (vmi && get_in(vmi, ["status", "nodeName"])) || "—",
      guest_os_config(vm),
      guest_os_agent(vmi),
      get_in(vm, ["metadata", "creationTimestamp"]) || "",
      vmi_started(vmi),
      "",
      to_cell(get_in(vm, ["spec", "runStrategy"])),
      live_migratable_display(get_in(vm, ["spec", "template", "spec", "evictionStrategy"])),
      to_cell(get_in(vm, ["spec", "template", "spec", "evictionStrategy"])),
      to_cell(vmi && get_in(vmi, ["status", "guestAgentInfo"]) != nil),
      to_cell(vmi && get_in(vmi, ["status", "guestAgentInfo", "version"])),
      domain_resource_field(vm, "requests", "cpu"),
      domain_resource_field(vm, "limits", "cpu"),
      domain_resource_field(vm, "requests", "memory")
    ]
  end

  # KubeVirt: `cores` per socket; guest CPU count = sockets * cores * threads (default 1 for missing parts).
  defp virtual_machine_cpu_columns(_vm, vmi, dom) when is_map(dom) do
    vm_cpu = Map.get(dom, "cpu") || %{}
    vmi_cpu = (vmi && get_in(vmi, ["spec", "domain", "cpu"])) || %{}

    if vm_cpu == %{} and vmi_cpu == %{} do
      {"", "", ""}
    else
      sockets = cpu_int_prefer_vm(vm_cpu, vmi_cpu, "sockets", 1)
      cores = cpu_int_prefer_vm(vm_cpu, vmi_cpu, "cores", 1)
      threads = cpu_int_prefer_vm(vm_cpu, vmi_cpu, "threads", 1)
      total = max(1, sockets) * max(1, cores) * max(1, threads)

      {to_cell(cores), to_cell(sockets), to_cell(total)}
    end
  end

  defp cpu_int_prefer_vm(vm_cpu, vmi_cpu, key, default) do
    v1 = Map.get(vm_cpu, key)
    v2 = Map.get(vmi_cpu, key)

    cond do
      is_integer(v1) and v1 > 0 -> v1
      is_integer(v2) and v2 > 0 -> v2
      true -> default
    end
  end

  defp instancetype_ref(vm) do
    get_in(vm, ["spec", "instancetype", "name"]) ||
      get_in(vm, [
        "spec",
        "template",
        "metadata",
        "annotations",
        "vm.kubevirt.io/instancetype-name"
      ]) ||
      ""
  end

  defp guest_os_config(vm) do
    get_in(vm, ["spec", "template", "metadata", "annotations", "vm.kubevirt.io/os"]) || ""
  end

  defp guest_os_agent(nil), do: ""

  defp guest_os_agent(vmi) do
    get_in(vmi, ["status", "guestAgentInfo", "os", "prettyName"]) ||
      get_in(vmi, ["status", "guestAgentInfo", "os", "name"]) || ""
  end

  defp dns_name_from_vm(vm, vmi) do
    ha = get_in(vm, ["spec", "template", "metadata", "annotations", "vm.kubevirt.io/hostname"])

    cond do
      is_binary(ha) and ha != "" ->
        ha

      is_map(vmi) ->
        get_in(vmi, ["status", "guestAgentInfo", "hostname"]) || ""

      true ->
        ""
    end
  end

  defp live_migratable_display(nil), do: ""

  defp live_migratable_display("NoneExternal"), do: "false"

  defp live_migratable_display(_), do: "true"

  defp vmi_started(nil), do: ""

  defp vmi_started(vmi) do
    conds = get_in(vmi, ["status", "conditions"]) || []

    case Enum.find(conds, &(&1["type"] == "Ready")) do
      %{"lastTransitionTime" => t} -> t
      _ -> ""
    end
  end

  defp first_network_name(ifaces) do
    case List.first(ifaces) do
      nil -> ""
      i -> interface_network_name(i)
    end
  end

  defp interface_network_name(iface) do
    cond do
      Map.has_key?(iface, "masquerade") -> "Pod"
      n = get_in(iface, ["multus", "networkName"]) -> n
      true -> Map.get(iface, "name") || ""
    end
  end

  defp interface_type(iface) do
    cond do
      Map.has_key?(iface, "masquerade") -> "masquerade"
      Map.has_key?(iface, "bridge") -> "bridge"
      Map.has_key?(iface, "sriov") -> "sriov"
      true -> ""
    end
  end

  defp interface_status(vmi, name) when is_binary(name) do
    ifaces = (vmi && get_in(vmi, ["status", "interfaces"])) || []

    Enum.find(ifaces, fn i -> Map.get(i, "name") == name end) || %{}
  end

  defp first_ip(st, key) do
    ips = Map.get(st, key) || []

    Enum.find_value(ips, "", fn ip ->
      if is_binary(ip) and String.contains?(ip, "."), do: ip, else: nil
    end)
  end

  defp primary_ip_from_interfaces(nil), do: ""

  defp primary_ip_from_interfaces(vmi) do
    ifaces = get_in(vmi, ["status", "interfaces"]) || []

    Enum.find_value(ifaces, "", fn i ->
      case Map.get(i, "ipAddress") do
        s when is_binary(s) and s != "" -> s
        _ -> first_ip(i, "ipAddresses")
      end
    end)
  end

  defp all_ips_from_interfaces(nil), do: ""

  defp all_ips_from_interfaces(vmi) do
    ifaces = get_in(vmi, ["status", "interfaces"]) || []

    ifaces
    |> Enum.flat_map(fn i ->
      [Map.get(i, "ipAddress") | List.wrap(Map.get(i, "ipAddresses"))]
      |> Enum.filter(&is_binary/1)
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp volumes_by_name(vm) do
    vols = get_in(vm, ["spec", "template", "spec", "volumes"]) || []
    Map.new(vols, fn v -> {Map.get(v, "name"), v} end)
  end

  defp volume_pvc_name(vol) do
    get_in(vol, ["persistentVolumeClaim", "claimName"])
  end

  defp pvc_index_by_key(pvcs) do
    Map.new(pvcs, fn p -> {{meta(p, "namespace"), meta(p, "name")}, p} end)
  end

  defp pvc_capacity(nil), do: ""

  defp pvc_capacity(pvc) do
    get_in(pvc, ["status", "capacity", "storage"]) ||
      get_in(pvc, ["spec", "resources", "requests", "storage"]) || ""
  end

  defp pvc_access_modes(nil), do: ""

  defp pvc_access_modes(pvc) do
    case get_in(pvc, ["spec", "accessModes"]) do
      list when is_list(list) -> Enum.join(list, ", ")
      _ -> ""
    end
  end

  defp vm_claiming_pvc_index(vms) do
    Enum.reduce(vms, %{}, fn vm, acc ->
      ns = meta(vm, "namespace")
      name = meta(vm, "name")
      vols = get_in(vm, ["spec", "template", "spec", "volumes"]) || []

      Enum.reduce(vols, acc, fn v, a ->
        case get_in(v, ["persistentVolumeClaim", "claimName"]) do
          c when is_binary(c) -> Map.put(a, {ns, c}, name)
          _ -> a
        end
      end)
    end)
  end

  defp domain_resource_field(vm, section, resource) do
    get_in(vm, [
      "spec",
      "template",
      "spec",
      "domain",
      "resources",
      section,
      resource
    ])
    |> to_cell()
  end

  defp hugepages_summary(vm) do
    pages = get_in(vm, ["spec", "template", "spec", "domain", "memory", "hugepages"]) || []

    Enum.map_join(pages, ", ", fn h ->
      "#{Map.get(h, "pageSize", "?")}=#{Map.get(h, "size", "?")}"
    end)
  end

  defp snapshot_ready?(s) do
    get_in(s, ["status", "readyToUse"]) == true
  end

  defp snapshot_phase(s) do
    case get_in(s, ["status", "phase"]) do
      nil ->
        case get_in(s, ["status", "conditions"]) do
          [c | _] when is_map(c) -> Map.get(c, "type", "")
          _ -> ""
        end

      p ->
        p
    end
  end

  defp migration_status_label(m) do
    case get_in(m, ["status", "phase"]) do
      nil -> ""
      p -> to_string(p)
    end
  end

  defp dv_source_summary(src) do
    cond do
      get_in(src, ["http", "url"]) ->
        {"http", get_in(src, ["http", "url"])}

      get_in(src, ["registry", "url"]) ->
        {"registry", get_in(src, ["registry", "url"])}

      get_in(src, ["s3", "url"]) ->
        {"s3", get_in(src, ["s3", "url"])}

      Map.has_key?(src, "blank") ->
        {"blank", ""}

      Map.has_key?(src, "pvc") ->
        {"pvc", get_in(src, ["pvc", "name"]) || ""}

      true ->
        {"", inspect(Map.keys(src))}
    end
  end

  defp event_ref(ev) do
    get_in(ev, ["regarding"]) || get_in(ev, ["involvedObject"]) || %{}
  end

  defp event_message(ev) do
    get_in(ev, ["note"]) || get_in(ev, ["message"]) || ""
  end

  defp event_type(ev) do
    get_in(ev, ["type"]) || get_in(ev, ["reportingController"]) || ""
  end

  defp event_count(ev) do
    case get_in(ev, ["series", "count"]) do
      nil -> get_in(ev, ["count"]) || 1
      c -> c
    end
  end

  defp event_first(ev) do
    get_in(ev, ["deprecatedFirstTimestamp"]) ||
      get_in(ev, ["eventTime"]) ||
      get_in(ev, ["metadata", "creationTimestamp"]) || ""
  end

  defp event_last(ev) do
    get_in(ev, ["deprecatedLastTimestamp"]) ||
      get_in(ev, ["series", "lastObservedTime"]) ||
      get_in(ev, ["lastTimestamp"]) || ""
  end

  defp event_source(ev) do
    get_in(ev, ["reportingController"]) ||
      get_in(ev, ["source", "component"]) ||
      get_in(ev, ["deprecatedSource", "component"]) || ""
  end

  defp event_sort_key(ev) do
    t = event_last(ev)
    if t == "", do: event_first(ev), else: t
  end

  defp usage_pct(hard, used) when is_binary(hard) and is_binary(used) do
    with {h, _} <- parse_qty_num(hard),
         {u, _} <- parse_qty_num(used),
         true <- h > 0 do
      "#{Float.round(u * 100 / h, 1)}%"
    else
      _ -> ""
    end
  end

  defp usage_pct(_, _), do: ""

  defp parse_qty_num(s) do
    s = String.trim(to_string(s))

    case Regex.run(~r/^([0-9]+)/, s) do
      [_, n] -> {String.to_integer(n), s}
      _ -> :error
    end
  end

  defp vmis_by_node(vmis) do
    Enum.group_by(vmis, &get_in(&1, ["status", "nodeName"]), fn x -> x end)
    |> Map.delete(nil)
    |> Map.delete("")
  end

  defp vmi_guest_cpu_count(nil), do: 0

  defp vmi_guest_cpu_count(vmi) do
    c = get_in(vmi, ["spec", "domain", "cpu", "cores"])
    if is_integer(c), do: c, else: 0
  end

  defp vmi_memory_bytes(nil), do: 0

  defp vmi_memory_bytes(vmi) do
    mem_bytes_from_quantity(get_in(vmi, ["spec", "domain", "memory", "guest"]) || "")
  end

  defp mem_bytes_from_quantity(q) when is_binary(q) do
    q = String.trim(q)
    if q == "", do: 0, else: quantity_to_bytes(q)
  end

  defp domain_guest_cpu_total(dom, vmi) when is_map(dom) do
    sockets = Map.get(dom, "sockets") || 1
    cores = Map.get(dom, "cores") || 1
    threads = Map.get(dom, "threads") || 1

    case vmi do
      nil -> sockets * cores * threads
      _ -> max(vmi_guest_cpu_count(vmi), sockets * cores * threads)
    end
  end

  defp node_ready_status(n) do
    conds = get_in(n, ["status", "conditions"]) || []

    case Enum.find(conds, &(&1["type"] == "Ready")) do
      %{"status" => "True"} -> "Ready"
      %{"status" => "False"} -> "NotReady"
      _ -> "Unknown"
    end
  end

  defp node_ready_counts(nodes) do
    Enum.reduce(nodes, {0, 0}, fn n, {r, nr} ->
      case node_ready_status(n) do
        "Ready" -> {r + 1, nr}
        _ -> {r, nr + 1}
      end
    end)
  end

  defp node_roles(n) do
    labels = get_in(n, ["metadata", "labels"]) || %{}

    roles =
      []
      |> maybe_add_role(Map.get(labels, "node-role.kubernetes.io/control-plane"), "control-plane")
      |> maybe_add_role(Map.get(labels, "node-role.kubernetes.io/master"), "master")
      |> maybe_add_role(Map.get(labels, "node-role.kubernetes.io/worker"), "worker")

    if roles == [] do
      "worker"
    else
      Enum.join(roles, ", ")
    end
  end

  defp maybe_add_role(acc, v, label) when v != nil, do: [label | acc]
  defp maybe_add_role(acc, _, _), do: acc

  defp control_plane_count(nodes) do
    Enum.count(nodes, fn n ->
      labels = get_in(n, ["metadata", "labels"]) || %{}

      Map.has_key?(labels, "node-role.kubernetes.io/control-plane") or
        Map.has_key?(labels, "node-role.kubernetes.io/master")
    end)
  end

  defp node_schedulable?(n) do
    get_in(n, ["spec", "unschedulable"]) != true
  end

  defp format_taints(n) do
    ts = get_in(n, ["spec", "taints"]) || []

    Enum.map_join(ts, "; ", fn t ->
      "#{Map.get(t, "key")}=#{Map.get(t, "value")}:#{Map.get(t, "effect")}"
    end)
  end

  defp first_node_kubelet_version(nodes) do
    case List.first(nodes) do
      nil -> ""
      n -> get_in(n, ["status", "nodeInfo", "kubeletVersion"]) || ""
    end
  end

  defp sum_node_cpu_cores(nodes) do
    nodes
    |> Enum.map(&get_in(&1, ["status", "capacity", "cpu"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&cpu_string_to_cores/1)
    |> Enum.sum()
  end

  defp cpu_string_to_cores(s) when is_binary(s) do
    s = String.trim(s)

    cond do
      String.ends_with?(s, "m") ->
        case Integer.parse(String.trim_trailing(s, "m")) do
          {m, _} -> max(1, div(m + 500, 1000))
          :error -> 0
        end

      true ->
        case Integer.parse(s) do
          {n, _} -> n
          :error -> 0
        end
    end
  end

  defp sum_node_memory_human(nodes) do
    total =
      nodes
      |> Enum.map(&get_in(&1, ["status", "capacity", "memory"]))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&quantity_to_bytes/1)
      |> Enum.sum()

    format_bytes(total)
  end

  defp quantity_to_bytes(s) when is_binary(s) do
    s = String.trim(s)

    cond do
      s == "" ->
        0

      Regex.match?(~r/^[0-9]+$/, s) ->
        String.to_integer(s)

      true ->
        case Regex.run(~r/^([0-9]+(?:\.[0-9]+)?)\s*([A-Za-z]*)$/i, s) do
          [_, num_str, suf] ->
            case Float.parse(num_str) do
              {n, _} -> round(n * mem_suffix_multiplier(suf))
              :error -> 0
            end

          _ ->
            0
        end
    end
  end

  defp mem_suffix_multiplier(suf) do
    case String.trim(suf) do
      "Ki" -> 1024
      "Mi" -> 1024 ** 2
      "Gi" -> 1024 ** 3
      "Ti" -> 1024 ** 4
      "Pi" -> 1024 ** 5
      "K" -> 1000
      "M" -> 1_000_000
      "G" -> 1_000_000_000
      "T" -> 1_000_000_000_000
      _ -> 1
    end
  end

  defp format_bytes(0), do: "0"

  defp format_bytes(b) when is_integer(b) and b > 0 do
    gib = b / (1024 * 1024 * 1024)

    cond do
      gib >= 1024 -> "#{Float.round(gib / 1024, 2)} TiB"
      gib >= 1 -> "#{Float.round(gib, 2)} GiB"
      true -> "#{Float.round(b / (1024 * 1024), 2)} MiB"
    end
  end

  defp format_local(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp vmi_index(vmis) do
    for vmi <- vmis, into: %{} do
      {{meta(vmi, "namespace"), meta(vmi, "name")}, vmi}
    end
  end

  defp format_label_map(m) when map_size(m) == 0, do: ""

  defp format_label_map(m) do
    m
    |> Enum.reject(fn {k, _} -> String.starts_with?(to_string(k), "kubectl.kubernetes.io/") end)
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end

  defp meta(obj, key) do
    case get_in(obj, ["metadata", key]) do
      nil -> ""
      val -> to_string(val)
    end
  end

  defp to_cell(val), do: VmExport.to_cell(val)
end
