defmodule KubevirtToolsWeb.DashboardLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.DashboardCharts
  alias KubevirtTools.KubeVirt
  alias KubevirtTools.KubeconfigStore

  @impl true
  def mount(_params, _session, socket) do
    token = socket.assigns.kubeconfig_token

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_scope, %{label: "Cluster session"})
     |> assign(:active_tab, :dashboard)
     |> assign_async(:kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab_atom =
      case tab do
        "dashboard" -> :dashboard
        "vms" -> :vms
        "instances" -> :instances
        _ -> socket.assigns.active_tab
      end

    {:noreply, assign(socket, :active_tab, tab_atom)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    token = socket.assigns.kubeconfig_token

    {:noreply,
     socket
     |> assign_async(:kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 -mt-4 max-w-full min-w-0">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between border-b border-base-300/60 pb-4">
          <div>
            <p class="text-xs font-medium uppercase tracking-wider text-primary/90">Overview</p>
            <h1 class="text-2xl font-semibold tracking-tight mt-1">KubeVirt dashboard</h1>
            <p class="text-sm text-base-content/60 mt-1">
              Cluster snapshot, VM distribution, and storage — inspired by classic ops consoles.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs text-base-content/50 hidden sm:inline">Export</span>
            <button
              type="button"
              disabled
              class="btn btn-ghost btn-xs opacity-50 cursor-not-allowed"
              title="Coming soon"
            >
              XLSX
            </button>
            <button
              type="button"
              disabled
              class="btn btn-ghost btn-xs opacity-50 cursor-not-allowed"
              title="Coming soon"
            >
              CSV
            </button>
            <button
              type="button"
              phx-click="refresh"
              id="dashboard-refresh"
              class="btn btn-outline btn-sm gap-2"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
          </div>
        </div>

        <div class="mt-4">
          <.async_result :let={data} assign={@kubevirt}>
            <:loading>
              <div class="flex items-center gap-3 rounded-xl border border-base-300/70 bg-base-200/40 px-5 py-12 text-base-content/70">
                <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
                <span>Loading cluster snapshot…</span>
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="alert alert-error">
                <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                <span>Could not load cluster data. Try refreshing or signing in again.</span>
              </div>
            </:failed>

            <% m = metrics(data) %>
            <% snap = to_string(data.snapshot_at) %>
            <.daisy_tabs
              id="kubevirt-dashboard-tabs"
              active={@active_tab}
              event="set_tab"
              tabs={dashboard_tab_defs()}
              class="border-b border-base-300/50 pb-3 mb-0"
            />

            <div class="mt-5">
              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:dashboard}
                active={@active_tab}
                class="space-y-8 scroll-mt-24"
              >
                <div id="overview" class="space-y-8 pt-1">
                  <div class="flex flex-wrap items-center gap-2 text-xs text-base-content/55 min-h-[1.75rem]">
                    <span
                      :if={data.cluster}
                      class="badge badge-ghost badge-sm gap-1 font-mono px-3 py-2 h-auto whitespace-normal"
                    >
                      {data.user} @ {data.cluster}
                    </span>
                  </div>

                  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-4 2xl:grid-cols-7 gap-2 sm:gap-3">
                    <.stat_tile label="Total VMs" value={m.total_vms} highlight={:neutral} />
                    <.stat_tile label="Running" value={m.running} highlight={:success} />
                    <.stat_tile label="Stopped" value={m.stopped} highlight={:danger} />
                    <.stat_tile label="vCPUs (VMIs)" value={m.total_vcpus} highlight={:neutral} />
                    <.stat_tile
                      label="Nodes ready"
                      value={"#{m.nodes_ready}/#{m.nodes_total}"}
                      highlight={:neutral}
                    />
                    <.stat_tile label="PVCs" value={m.pvc_total} highlight={:neutral} />
                    <.stat_tile label="Running VMIs" value={m.vmi_running} highlight={:success} />
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3 md:gap-4 2xl:gap-5 min-w-0">
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-vm-status-#{snap}"}
                      title="VMs by status"
                      height="200px"
                      opts={DashboardCharts.vm_status_donut(m.running, m.stopped, m.other_vm)}
                    />
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-vm-per-node-#{snap}"}
                      title="VMIs per node"
                      height="200px"
                      opts={DashboardCharts.vms_per_node_bar(m.node_labels, m.node_vm_counts)}
                    />
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-vcpu-node-#{snap}"}
                      title="vCPU per node (VMIs)"
                      height="200px"
                      opts={
                        DashboardCharts.horizontal_bar(
                          "vCPUs",
                          m.node_labels,
                          m.node_vcpu_counts,
                          "#f87171"
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-mem-node-#{snap}"}
                      title="Memory per node (MiB, guest)"
                      height="200px"
                      opts={
                        DashboardCharts.horizontal_bar(
                          "MiB",
                          m.node_labels,
                          m.node_mem_mib,
                          "#4ade80"
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0 md:col-span-2 2xl:col-span-1"
                      id={"chart-pvc-class-#{snap}"}
                      title="PVCs per storage class"
                      height="200px"
                      opts={
                        DashboardCharts.pvc_storage_class_pie(m.pvc_class_labels, m.pvc_class_series)
                      }
                    />
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3 md:gap-4 2xl:gap-5 min-w-0">
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-pvc-status-#{snap}"}
                      title="PVC status"
                      height="200px"
                      opts={
                        DashboardCharts.pvc_status_donut(
                          m.pvc_bound,
                          m.pvc_pending,
                          m.pvc_lost,
                          m.pvc_other
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-node-load-#{snap}"}
                      title="Node distribution (placeholder)"
                      height="220px"
                      opts={
                        DashboardCharts.node_load_placeholder(
                          ["0–25%", "25–50%", "50–75%", "75–100%"],
                          m.load_placeholder_buckets
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0"
                      id={"chart-health-#{snap}"}
                      title="VMI phases"
                      height="200px"
                      opts={
                        DashboardCharts.vm_status_donut(
                          m.vmi_running,
                          m.vmi_not_running,
                          m.vmi_other_phase,
                          labels: ["Running", "Not running", "Other"],
                          empty_label: "No VMIs"
                        )
                      }
                    />
                  </div>
                </div>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:vms}
                active={@active_tab}
                class="space-y-3 scroll-mt-24 pt-1"
              >
                <section id="vms">
                  <h2 class="text-lg font-medium flex items-center gap-2">
                    <.icon name="hero-computer-desktop" class="size-5 text-primary" /> VirtualMachines
                  </h2>
                  <%= if data.vm_error do %>
                    <div class="alert alert-warning text-sm mt-3">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </div>
                  <% else %>
                    <div class="mt-3">
                      <.vm_table
                        items={data.vms}
                        empty_label="No VirtualMachines found."
                        id_prefix="vm"
                      />
                    </div>
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:instances}
                active={@active_tab}
                class="space-y-3 scroll-mt-24 pt-1"
              >
                <section id="vmis">
                  <h2 class="text-lg font-medium flex items-center gap-2">
                    <.icon name="hero-cpu-chip" class="size-5 text-secondary" />
                    VirtualMachineInstances
                  </h2>
                  <%= if data.vmi_error do %>
                    <div class="alert alert-warning text-sm mt-3">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>Could not list VMIs ({vm_error_text(data.vmi_error)}).</span>
                    </div>
                  <% else %>
                    <div class="mt-3">
                      <.vmi_table items={data.vmis} empty_label="No VMIs found." id_prefix="vmi" />
                    </div>
                  <% end %>
                </section>
              </.tab_panel>
            </div>
          </.async_result>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :highlight, :atom, values: [:neutral, :success, :danger, :warning], default: :neutral

  defp stat_tile(assigns) do
    value_class =
      case assigns.highlight do
        :success -> "text-emerald-400"
        :danger -> "text-rose-400"
        :warning -> "text-amber-400"
        :neutral -> "text-base-content"
      end

    assigns = assign(assigns, :value_class, value_class)

    ~H"""
    <div class="rounded-xl border border-base-300/60 bg-base-200/40 px-4 py-3 transition hover:border-primary/30 hover:bg-base-200/70">
      <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50">
        {@label}
      </p>
      <p class={["text-xl font-semibold tabular-nums mt-1", @value_class]}>{@value}</p>
      <p :if={@sub} class="text-xs text-base-content/45 mt-0.5">{@sub}</p>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp vm_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>Phase</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@items == []}>
            <td colspan="4" class="text-center text-base-content/50 py-8">{@empty_label}</td>
          </tr>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs">{vm_meta(item, :namespace)}</td>
              <td class="font-medium">{vm_meta(item, :name)}</td>
              <td>
                <span class="badge badge-sm badge-outline">{vm_phase(item)}</span>
              </td>
              <td class="text-xs text-base-content/60">{vm_meta(item, :created)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp vmi_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>Phase</th>
            <th>Node</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@items == []}>
            <td colspan="4" class="text-center text-base-content/50 py-8">{@empty_label}</td>
          </tr>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs">{vm_meta(item, :namespace)}</td>
              <td class="font-medium">{vm_meta(item, :name)}</td>
              <td>
                <span class="badge badge-sm badge-outline">{vmi_phase(item)}</span>
              </td>
              <td class="font-mono text-xs text-base-content/70">{vmi_node(item)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp dashboard_tab_defs do
    [
      %{id: :dashboard, label: "Dashboard"},
      %{id: :vms, label: "VMs"},
      %{id: :instances, label: "Instances"},
      %{id: :snapshots, label: "Snapshots", disabled: true},
      %{id: :health, label: "Health", disabled: true}
    ]
  end

  defp load_kubevirt(token) do
    with {:ok, yaml} <- KubeconfigStore.get(token),
         {:ok, conn} <- K8s.Conn.from_string(yaml) do
      {vms, vm_err} = safe_list(&KubeVirt.list_virtual_machines/1, conn)
      {vmis, vmi_err} = safe_list(&KubeVirt.list_virtual_machine_instances/1, conn)
      {nodes, node_err} = safe_list(&ClusterInventory.list_nodes/1, conn)
      {pvcs, pvc_err} = safe_list(&ClusterInventory.list_pvcs/1, conn)

      {:ok,
       %{
         kubevirt: %{
           cluster: conn.cluster_name,
           user: conn.user_name,
           vms: vms,
           vmis: vmis,
           nodes: nodes,
           pvcs: pvcs,
           vm_error: vm_err,
           vmi_error: vmi_err,
           node_error: node_err,
           pvc_error: pvc_err,
           snapshot_at: System.system_time(:millisecond)
         }
       }}
    else
      :error ->
        {:error, :invalid_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_list(fun, conn) do
    case fun.(conn) do
      {:ok, items} -> {items, nil}
      {:error, reason} -> {[], reason}
    end
  end

  defp metrics(data) do
    vms = data.vms || []
    vmis = data.vmis || []
    nodes = data.nodes || []
    pvcs = data.pvcs || []

    {running, stopped, other} = vm_status_counts(vms)
    {vmi_run, vmi_not_run, vmi_other} = vmi_phase_counts(vmis)

    {labels, counts, vcpus, mems} =
      case node_aggregates(vmis) do
        {[], [], [], []} -> {["—"], [0], [0], [0]}
        tuple -> tuple
      end

    {pvc_bound, pvc_pending, pvc_lost, pvc_other} = pvc_status_counts(pvcs)

    {class_labels, class_series} =
      case pvc_by_storage_class(pvcs) do
        {[], []} -> {["No PVCs"], [0]}
        pair -> pair
      end

    nodes_total = length(nodes)
    nodes_ready = Enum.count(nodes, &node_ready?/1)
    load_buckets = placeholder_load_buckets(nodes_total)

    %{
      total_vms: length(vms),
      running: running,
      stopped: stopped,
      other_vm: other,
      total_vcpus: Enum.sum(Map.values(vcpu_by_vmi(vmis))),
      nodes_ready: nodes_ready,
      nodes_total: nodes_total,
      pvc_total: length(pvcs),
      node_labels: labels,
      node_vm_counts: counts,
      node_vcpu_counts: vcpus,
      node_mem_mib: mems,
      pvc_bound: pvc_bound,
      pvc_pending: pvc_pending,
      pvc_lost: pvc_lost,
      pvc_other: pvc_other,
      pvc_class_labels: class_labels,
      pvc_class_series: class_series,
      load_placeholder_buckets: load_buckets,
      vmi_running: vmi_run,
      vmi_not_running: vmi_not_run,
      vmi_other_phase: vmi_other
    }
  end

  defp vm_status_counts(vms) do
    Enum.reduce(vms, {0, 0, 0}, fn vm, {r, s, o} ->
      case String.downcase(vm_phase(vm)) do
        "running" -> {r + 1, s, o}
        "stopped" -> {r, s + 1, o}
        _ -> {r, s, o + 1}
      end
    end)
  end

  defp vmi_phase_counts(vmis) do
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

  defp vcpu_by_vmi(vmis) do
    for vmi <- vmis, into: %{} do
      name = vm_meta(vmi, :name)
      cores = vmi_vcpu_cores(vmi)
      {name, cores}
    end
  end

  defp vmi_vcpu_cores(vmi) do
    case get_in(vmi, ["spec", "domain", "cpu", "cores"]) do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  defp node_aggregates(vmis) do
    grouped =
      Enum.group_by(vmis, fn vmi ->
        n = vmi_node(vmi)
        if n in [nil, "", "—"], do: "Unscheduled", else: n
      end)

    labels = grouped |> Map.keys() |> Enum.sort()

    counts = Enum.map(labels, fn l -> length(Map.get(grouped, l, [])) end)

    vcpus =
      Enum.map(labels, fn l ->
        Map.get(grouped, l, [])
        |> Enum.map(&vmi_vcpu_cores/1)
        |> Enum.sum()
      end)

    mems =
      Enum.map(labels, fn l ->
        Map.get(grouped, l, [])
        |> Enum.map(&vmi_memory_mib/1)
        |> Enum.sum()
      end)

    {labels, counts, vcpus, mems}
  end

  defp vmi_memory_mib(vmi) do
    guest = get_in(vmi, ["spec", "domain", "memory", "guest"]) || ""

    guest
    |> to_string()
    |> String.trim()
    |> parse_memory_to_mib()
  end

  defp parse_memory_to_mib(""), do: 0

  defp parse_memory_to_mib(s) do
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

  defp memory_suffix_to_mib_mult("ki"), do: 1 / 1024
  defp memory_suffix_to_mib_mult("k"), do: 1 / 1024
  defp memory_suffix_to_mib_mult("mi"), do: 1
  defp memory_suffix_to_mib_mult("m"), do: 1
  defp memory_suffix_to_mib_mult("gi"), do: 1024
  defp memory_suffix_to_mib_mult("g"), do: 1024
  defp memory_suffix_to_mib_mult(_), do: 1

  defp pvc_status_counts(pvcs) do
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

  defp pvc_by_storage_class(pvcs) do
    grouped =
      Enum.group_by(pvcs, fn pvc ->
        get_in(pvc, ["spec", "storageClassName"]) || "default"
      end)

    labels = grouped |> Map.keys() |> Enum.sort()
    series = Enum.map(labels, fn l -> length(Map.get(grouped, l, [])) end)
    {labels, series}
  end

  defp node_ready?(node) do
    conditions = get_in(node, ["status", "conditions"]) || []

    Enum.any?(conditions, fn c ->
      c["type"] == "Ready" and c["status"] == "True"
    end)
  end

  defp placeholder_load_buckets(0), do: [0, 0, 0, 0]
  defp placeholder_load_buckets(n) when n <= 2, do: [n, 0, 0, 0]
  defp placeholder_load_buckets(n) when n <= 4, do: [div(n, 2), n - div(n, 2), 0, 0]
  defp placeholder_load_buckets(n), do: [div(n, 4), div(n, 4), div(n, 4), n - 3 * div(n, 4)]

  defp vm_error_text(%K8s.Client.HTTPError{message: m}) when is_binary(m), do: m
  defp vm_error_text(%{message: m}) when is_binary(m), do: m
  defp vm_error_text(other), do: inspect(other)

  defp vm_meta(item, :namespace), do: get_in(item, ["metadata", "namespace"]) || "—"
  defp vm_meta(item, :name), do: get_in(item, ["metadata", "name"]) || "—"

  defp vm_meta(item, :created) do
    case get_in(item, ["metadata", "creationTimestamp"]) do
      nil -> "—"
      ts -> ts
    end
  end

  defp vm_phase(item) do
    get_in(item, ["status", "printableStatus"]) || "—"
  end

  defp vmi_phase(item) do
    get_in(item, ["status", "phase"]) || "—"
  end

  defp vmi_node(item) do
    get_in(item, ["status", "nodeName"]) || "—"
  end
end
