defmodule KubevirtToolsWeb.DashboardLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.DashboardCharts
  alias KubevirtTools.KubeVirt
  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.PrometheusSetup

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

                  <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 sm:gap-3">
                    <%= if m.usage_cpu_overlay do %>
                      <.usage_stat_placeholder
                        id="dashboard-usage-cpu-setup"
                        label="Node CPU usage"
                        message={m.usage_cpu_overlay}
                      />
                    <% else %>
                      <.stat_tile
                        label="Node CPU usage"
                        value={m.usage_cpu_value}
                        sub={m.usage_cpu_sub}
                        highlight={m.usage_cpu_highlight}
                      />
                    <% end %>
                    <%= if m.usage_mem_overlay do %>
                      <.usage_stat_placeholder
                        id="dashboard-usage-mem-setup"
                        label="Node memory usage"
                        message={m.usage_mem_overlay}
                      />
                    <% else %>
                      <.stat_tile
                        label="Node memory usage"
                        value={m.usage_mem_value}
                        sub={m.usage_mem_sub}
                        highlight={m.usage_mem_highlight}
                      />
                    <% end %>
                    <%= if m.usage_storage_overlay do %>
                      <.usage_stat_placeholder
                        id="dashboard-usage-storage-setup"
                        label="Cluster storage"
                        message={m.usage_storage_overlay}
                      />
                    <% else %>
                      <.stat_tile
                        label="Cluster storage"
                        value={m.usage_storage_value}
                        sub={m.usage_storage_sub}
                        highlight={m.usage_storage_highlight}
                      />
                    <% end %>
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
                      class="min-w-0"
                      id={"chart-nodes-scheduling-#{snap}"}
                      title="Cluster nodes (scheduling)"
                      height="200px"
                      opts={
                        DashboardCharts.node_scheduling_donut(
                          m.nodes_schedulable,
                          m.nodes_cordoned,
                          m.nodes_not_ready
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0"
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
                    <.node_load_chart_placeholder id={"node-load-chart-placeholder-#{snap}"} />
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

  attr :label, :string, required: true
  attr :message, :string, required: true
  attr :id, :string, default: nil

  defp usage_stat_placeholder(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative overflow-hidden rounded-xl border border-dashed border-warning/40 bg-base-200/25 min-h-[5.85rem]"
    >
      <div class="absolute inset-0 z-10 flex items-center justify-center p-2 sm:p-3">
        <div
          role="alert"
          class={[
            "alert alert-warning shadow-md max-h-full overflow-y-auto",
            "py-2 px-3 gap-2 text-xs leading-snug max-w-[min(100%,18rem)] w-full"
          ]}
        >
          <.icon name="hero-puzzle-piece" class="size-5 shrink-0 opacity-90" />
          <div class="min-w-0">
            <p class="text-[0.6rem] font-semibold uppercase tracking-wide text-warning-content/80">
              {@label} — setup required
            </p>
            <p class="mt-1 text-warning-content/95">{@message}</p>
          </div>
        </div>
      </div>
      <div class="p-4 pt-11 space-y-2 pointer-events-none opacity-25">
        <div class="skeleton h-3 w-24"></div>
        <div class="skeleton h-8 w-16"></div>
        <div class="skeleton h-3 w-32"></div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true

  defp node_load_chart_placeholder(assigns) do
    ~H"""
    <section
      id={@id}
      class={[
        "rounded-lg border border-dashed border-warning/45 bg-base-100/35 shadow-sm",
        "p-3 min-w-0 w-full overflow-hidden flex flex-col gap-1.5"
      ]}
    >
      <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/65 shrink-0 leading-tight">
        Node load distribution
      </h3>
      <div class="relative w-full min-w-0 shrink-0 rounded-md overflow-hidden border border-base-300/40 bg-base-200/20">
        <div class="h-[220px] w-full relative">
          <div class={[
            "absolute inset-0 z-10 flex items-center justify-center p-2 sm:p-3",
            "bg-base-300/50 backdrop-blur-[2px]"
          ]}>
            <div
              role="alert"
              class={[
                "alert alert-warning shadow-lg max-h-full overflow-y-auto",
                "py-2.5 px-3 gap-2.5 text-xs leading-snug max-w-[min(100%,21rem)]"
              ]}
            >
              <.icon name="hero-puzzle-piece" class="size-5 shrink-0 opacity-90" />
              <div class="min-w-0">
                <p class="font-semibold text-[0.65rem] uppercase tracking-wide text-warning-content/90">
                  Placeholder — connect Prometheus
                </p>
                <p class="mt-1.5 text-warning-content/95">
                  {node_load_chart_placeholder_message()}
                </p>
              </div>
            </div>
          </div>
          <div class="absolute inset-0 flex flex-col justify-center gap-3.5 px-3 py-4 pointer-events-none opacity-[0.22]">
            <div class="flex items-center gap-2">
              <div class="skeleton h-2.5 w-11 shrink-0"></div>
              <div class="skeleton h-6 flex-1 rounded max-w-[92%]"></div>
            </div>
            <div class="flex items-center gap-2">
              <div class="skeleton h-2.5 w-11 shrink-0"></div>
              <div class="skeleton h-6 flex-1 rounded max-w-[58%]"></div>
            </div>
            <div class="flex items-center gap-2">
              <div class="skeleton h-2.5 w-11 shrink-0"></div>
              <div class="skeleton h-6 flex-1 rounded max-w-[76%]"></div>
            </div>
            <div class="flex items-center gap-2">
              <div class="skeleton h-2.5 w-11 shrink-0"></div>
              <div class="skeleton h-6 flex-1 rounded max-w-[40%]"></div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp node_load_chart_placeholder_message do
    join_prometheus_hint(
      "This chart does not show live data yet. Deploy Prometheus (kube-prometheus-stack is a common choice) " <>
        "and scrape kubelet / cAdvisor (and related targets) so per-node load can be charted here once this panel is wired to queries."
    )
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
      {node_metrics, metrics_err} = safe_list(&ClusterMetrics.list_node_metrics/1, conn)

      {:ok,
       %{
         kubevirt: %{
           cluster: conn.cluster_name,
           user: conn.user_name,
           vms: vms,
           vmis: vmis,
           nodes: nodes,
           pvcs: pvcs,
           node_metrics: node_metrics,
           metrics_error: metrics_err,
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
    {nodes_schedulable, nodes_cordoned, nodes_not_ready} = node_scheduling_counts(nodes)

    node_metrics = Map.get(data, :node_metrics) || []
    metrics_err = Map.get(data, :metrics_error)
    usage = ClusterMetrics.usage_summary(nodes, node_metrics, pvcs)
    usage_cpu_overlay = usage_node_metric_overlay(usage.cpu, metrics_err)
    usage_mem_overlay = usage_node_metric_overlay(usage.memory, metrics_err)
    usage_storage_overlay = usage_storage_overlay_card(usage.storage)
    {u_cpu_val, u_cpu_sub, u_cpu_hi} = usage_card_fields(usage.cpu)
    {u_mem_val, u_mem_sub, u_mem_hi} = usage_card_fields(usage.memory)
    {u_sto_val, u_sto_sub, u_sto_hi} = usage_card_fields(usage.storage)

    %{
      total_vms: length(vms),
      running: running,
      stopped: stopped,
      other_vm: other,
      total_vcpus: Enum.sum(Map.values(vcpu_by_vmi(vmis))),
      nodes_ready: nodes_ready,
      nodes_schedulable: nodes_schedulable,
      nodes_cordoned: nodes_cordoned,
      nodes_not_ready: nodes_not_ready,
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
      vmi_running: vmi_run,
      vmi_not_running: vmi_not_run,
      vmi_other_phase: vmi_other,
      usage_cpu_value: u_cpu_val,
      usage_cpu_sub: u_cpu_sub,
      usage_cpu_highlight: u_cpu_hi,
      usage_mem_value: u_mem_val,
      usage_mem_sub: u_mem_sub,
      usage_mem_highlight: u_mem_hi,
      usage_storage_value: u_sto_val,
      usage_storage_sub: u_sto_sub,
      usage_storage_highlight: u_sto_hi,
      usage_cpu_overlay: usage_cpu_overlay,
      usage_mem_overlay: usage_mem_overlay,
      usage_storage_overlay: usage_storage_overlay
    }
  end

  defp usage_node_metric_overlay({:ok, _, _}, _metrics_err), do: nil

  defp usage_node_metric_overlay({:unavailable, _, hint}, metrics_err) do
    case format_node_metrics_api_blocker(metrics_err) do
      nil -> usage_node_metric_hint_sentence(hint)
      msg -> msg
    end
  end

  defp format_node_metrics_api_blocker(nil), do: nil

  defp format_node_metrics_api_blocker({:error, reason}) do
    format_node_metrics_api_blocker(reason)
  end

  defp format_node_metrics_api_blocker(%K8s.Client.APIError{reason: "Forbidden", message: msg})
       when is_binary(msg) do
    join_prometheus_hint(
      "Set up Prometheus (including kubelet scraping and usually metrics-server for metrics.k8s.io); " <>
        "your account also needs permission to list NodeMetrics. #{msg}"
    )
  end

  defp format_node_metrics_api_blocker(%K8s.Client.APIError{reason: "NotFound", message: msg})
       when is_binary(msg) do
    join_prometheus_hint(
      "metrics.k8s.io / NodeMetrics are not available—deploy Prometheus with a standard stack " <>
        "(e.g. kube-prometheus-stack) that installs metrics-server and scrapes kubelets. #{msg}"
    )
  end

  defp format_node_metrics_api_blocker(%K8s.Client.APIError{reason: reason, message: msg})
       when is_binary(reason) and is_binary(msg) do
    join_prometheus_hint("NodeMetrics could not be read (#{reason}): #{msg}")
  end

  defp format_node_metrics_api_blocker(%K8s.Client.APIError{} = e) do
    join_prometheus_hint("NodeMetrics could not be read: #{Exception.message(e)}")
  end

  defp format_node_metrics_api_blocker(%K8s.Client.HTTPError{} = e) do
    msg = Exception.message(e)

    cond do
      http_error_status?(msg, 404) ->
        join_prometheus_hint(
          "metrics.k8s.io / NodeMetrics are not reachable—deploy Prometheus with kube-prometheus-stack " <>
            "(or similar) so metrics-server and scraping are in place. #{msg}"
        )

      http_error_status?(msg, 403) ->
        join_prometheus_hint(
          "Prometheus-style monitoring should expose NodeMetrics; your account needs permission to list them. #{msg}"
        )

      true ->
        join_prometheus_hint("NodeMetrics could not be read: #{msg}")
    end
  end

  defp format_node_metrics_api_blocker(other) do
    join_prometheus_hint("NodeMetrics could not be read: #{inspect(other)}")
  end

  defp http_error_status?(message, code) when is_binary(message) and is_integer(code) do
    m = String.downcase(message)
    String.contains?(m, Integer.to_string(code)) or String.contains?(m, " #{code} ")
  end

  defp usage_node_metric_hint_sentence("Setup Prometheus (CPU)") do
    join_prometheus_hint(
      "Deploy Prometheus (typically via kube-prometheus-stack) so kubelet/cAdvisor and metrics.k8s.io feed NodeMetrics for CPU usage."
    )
  end

  defp usage_node_metric_hint_sentence("Setup Prometheus (memory)") do
    join_prometheus_hint(
      "Deploy Prometheus (typically via kube-prometheus-stack) so kubelet/cAdvisor and metrics.k8s.io feed NodeMetrics for memory usage."
    )
  end

  defp usage_node_metric_hint_sentence("Install metrics-server (CPU)"),
    do: usage_node_metric_hint_sentence("Setup Prometheus (CPU)")

  defp usage_node_metric_hint_sentence("Install metrics-server (memory)"),
    do: usage_node_metric_hint_sentence("Setup Prometheus (memory)")

  defp usage_node_metric_hint_sentence("CPU: could not match nodes to metrics") do
    join_prometheus_hint(
      "NodeMetrics exist but could not be matched to your nodes—check Prometheus scrape config, node names, and RBAC."
    )
  end

  defp usage_node_metric_hint_sentence("Memory: could not match nodes to metrics") do
    join_prometheus_hint(
      "NodeMetrics exist but could not be matched to your nodes—check Prometheus scrape config, node names, and RBAC."
    )
  end

  defp usage_node_metric_hint_sentence(other) when is_binary(other) do
    join_prometheus_hint(other)
  end

  defp usage_storage_overlay_card({:ok, _, _}), do: nil

  defp usage_storage_overlay_card({:unavailable, _, hint}) do
    join_prometheus_hint(
      "This card needs PVC storage requests and/or node allocatable ephemeral-storage. (#{hint}) " <>
        "Use Prometheus to scrape storage- and kubelet-related metrics for richer dashboards."
    )
  end

  defp join_prometheus_hint(primary) when is_binary(primary) do
    String.trim_trailing(primary) <> " " <> PrometheusSetup.endpoint_env_hint()
  end

  defp usage_card_fields({:ok, value, sub}),
    do: {value, sub, ClusterMetrics.highlight_for_usage({:ok, value, sub})}

  defp usage_card_fields({:unavailable, value, sub}), do: {value, sub, :neutral}

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

  defp node_cordoned?(node) do
    get_in(node, ["spec", "unschedulable"]) == true
  end

  defp node_scheduling_counts(nodes) do
    Enum.reduce(nodes, {0, 0, 0}, fn node, {sched, cord, down} ->
      ready = node_ready?(node)
      cordoned = node_cordoned?(node)

      cond do
        not ready ->
          {sched, cord, down + 1}

        ready and cordoned ->
          {sched, cord + 1, down}

        true ->
          {sched + 1, cord, down}
      end
    end)
  end

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
