defmodule KubevirtToolsWeb.DashboardLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  alias KubevirtTools.ClusterExportLists
  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.ClusterVersion
  alias KubevirtTools.K8sSafeError
  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.DashboardCharts
  alias KubevirtTools.K8sConn
  alias KubevirtTools.KubeVirt
  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.VmPresentation
  alias KubevirtTools.VmTopology
  alias KubevirtTools.PrometheusClient
  alias KubevirtTools.PrometheusMetricsServer
  alias KubevirtTools.PrometheusSetup

  import VmPresentation

  @cluster_usage_prometheus_hint "Prometheus not detected, either install it or set PROMETHEUS_URL to where its running"

  defp auto_refresh_ms, do: KubevirtTools.EnvConfig.int("POLL_INTERVAL_MS", 60_000)

  # Per-tab column filters. Empty string means "All" (no filter applied).
  @default_filters %{
    "vms" => %{"search" => "", "phase" => "", "node" => "", "agent" => "", "os" => ""},
    "networks" => %{"search" => "", "binding" => "", "vmi_phase" => ""},
    "disks" => %{"search" => "", "volume_kind" => "", "storage_class" => "", "pvc_phase" => ""},
    "storage_classes" => %{"search" => "", "provisioner" => ""},
    "nodes" => %{"search" => "", "ready" => "", "role" => "", "os" => ""}
  }

  # Per-tab column sort. `nil` means "no active sort" (rows keep their
  # natural/default order); a {field, direction} tuple overrides it.
  @default_sort %{
    "vms" => nil,
    "networks" => nil,
    "disks" => nil,
    "storage_classes" => nil,
    "nodes" => nil
  }

  @impl true
  def mount(params, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:current_scope, %{})
      |> assign(:active_tab, tab_atom_from_string(params["tab"], :dashboard))
      |> assign(:prometheus_live, nil)
      |> assign(:filters, @default_filters)
      |> assign(:sort, @default_sort)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(KubevirtTools.PubSub, PrometheusMetricsServer.topic())
        Process.send_after(self(), :auto_refresh, auto_refresh_ms())

        assign(socket, :prometheus_live, PrometheusMetricsServer.get_latest())
      else
        socket
      end

    {:ok,
     socket
     |> assign_async(:kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    tab_atom = tab_atom_from_string(tab, socket.assigns.active_tab)

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
  def handle_event("set_filter", %{"tab" => tab, "field" => field, "value" => value}, socket) do
    filters = put_in(socket.assigns.filters, [tab, field], value)
    {:noreply, assign(socket, :filters, filters)}
  end

  @impl true
  def handle_event("clear_filters", %{"tab" => tab}, socket) do
    filters = Map.put(socket.assigns.filters, tab, Map.fetch!(@default_filters, tab))
    {:noreply, assign(socket, :filters, filters)}
  end

  @impl true
  def handle_event("sort", %{"tab" => tab, "field" => field}, socket) do
    next =
      case Map.get(socket.assigns.sort, tab) do
        {^field, :asc} -> {field, :desc}
        {^field, :desc} -> nil
        _ -> {field, :asc}
      end

    {:noreply, assign(socket, :sort, Map.put(socket.assigns.sort, tab, next))}
  end

  defp tab_atom_from_string(tab, default) do
    case tab do
      "dashboard" -> :dashboard
      "vms" -> :vms
      "networks" -> :networks
      "disks" -> :disks
      "storage_classes" -> :storage_classes
      "nodes" -> :nodes
      "vm_topology" -> :vm_topology
      _ -> default
    end
  end

  @impl true
  def handle_info(:auto_refresh, socket) do
    Process.send_after(self(), :auto_refresh, auto_refresh_ms())
    token = socket.assigns.kubeconfig_token

    {:noreply, assign_async(socket, :kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def handle_info({:prometheus_metrics, msg}, socket) do
    {:noreply, assign(socket, :prometheus_live, msg)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-6 -mt-4 max-w-full min-w-0">
        <div class="mt-4">
          <.async_result :let={data} assign={@kubevirt}>
            <:loading>
              <div class="space-y-6">
                <div class="border-b border-base-300/60 pb-4">
                  <p class="text-xs font-medium uppercase tracking-wider text-primary/90">Overview</p>
                  <h1 class="text-2xl font-semibold tracking-tight mt-1">KubeVirt Tools</h1>
                  <p class="text-sm text-base-content/60 mt-1">
                    Cluster-wide Virtualization Insights
                  </p>
                </div>
                <.pp_paper
                  elevation={0}
                  class="flex items-center gap-3 border border-pp-outline/20 bg-pp-surface-variant/40 px-5 py-12 text-pp-on-surface/70"
                >
                  <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
                  <span>Loading cluster snapshot…</span>
                </.pp_paper>
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="space-y-4">
                <div class="border-b border-base-300/60 pb-4">
                  <p class="text-xs font-medium uppercase tracking-wider text-primary/90">Overview</p>
                  <h1 class="text-2xl font-semibold tracking-tight mt-1">KubeVirt Tools</h1>
                  <p class="text-sm text-base-content/60 mt-1">
                    Cluster-wide Virtualization Insights
                  </p>
                </div>
                <.pp_alert severity="error">
                  Could not load cluster data. Try refreshing or signing in again.
                </.pp_alert>
              </div>
            </:failed>

            <% m = metrics(data, @prometheus_live) %>
            <div class="flex flex-col gap-4 pb-3 lg:flex-row lg:items-center lg:justify-between">
              <div class="min-w-0">
                <p class="text-xs font-medium uppercase tracking-wider text-primary/90">Overview</p>
                <h1 class="text-2xl font-semibold tracking-tight mt-1">KubeVirt Tools</h1>
                <p class="text-sm text-base-content/60 mt-1">
                  Cluster-wide Virtualization Insights
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-xs text-pp-on-surface/50 hidden sm:inline">Export</span>
                <.link
                  href={~p"/export/vms.xlsx"}
                  target="_blank"
                  rel="noopener noreferrer"
                  id="dashboard-export-xlsx"
                  title="Download cluster inventory as Excel (VirtualMachines sheet matches CSV)"
                >
                  <.pp_button variant="text" class="text-xs px-3 py-1.5">XLSX</.pp_button>
                </.link>
                <.link
                  href={~p"/export/vms.csv"}
                  target="_blank"
                  rel="noopener noreferrer"
                  id="dashboard-export-csv"
                  title="Download VirtualMachines as CSV"
                >
                  <.pp_button variant="text" class="text-xs px-3 py-1.5">CSV</.pp_button>
                </.link>
                <.pp_button
                  variant="outlined"
                  phx-click="refresh"
                  id="dashboard-refresh"
                  class="text-xs"
                  title={"Also auto-refreshes every #{format_interval_label(auto_refresh_ms())}"}
                >
                  <:start_icon><.icon name="hero-arrow-path" class="size-4" /></:start_icon>
                  Refresh
                </.pp_button>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-x-3 gap-y-2 border-b border-base-300/50 pb-3 mb-0">
              <.daisy_tabs
                id="kubevirt-dashboard-tabs"
                active={@active_tab}
                event="set_tab"
                tabs={dashboard_tab_defs()}
                active_style={:outline_primary}
                class="min-w-0 flex-1"
              />
              <div
                id="dashboard-prometheus-nav-indicator"
                class="flex shrink-0 items-center border-l border-base-300/40 pl-3 lg:pl-4"
              >
                <.prometheus_compact_indicator connected?={m.prometheus_ok?} url={m.prometheus_url} />
              </div>
            </div>

            <div class="mt-5">
              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:dashboard}
                active={@active_tab}
                class="space-y-8 scroll-mt-24"
              >
                <div id="overview" class="space-y-8 pt-1">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-chart-bar-square" class="size-5 text-pp-primary" />
                      Cluster overview
                      <.tab_heading_hint
                        id="dashboard-tab-overview-hint"
                        tip="Metrics and charts from a one-time cluster snapshot (VirtualMachines, VMIs, nodes, PVCs, storage classes, optional Prometheus). Use Refresh to reload data."
                      />
                    </h2>
                  </div>
                  <div
                    :if={data.cluster}
                    class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs min-h-[1.75rem]"
                  >
                    <span class="shrink-0 font-semibold uppercase tracking-wide text-pp-on-surface/55">
                      Current context
                    </span>
                    <.pp_chip size="small" class="font-mono h-auto whitespace-normal">
                      {data.user} @ {data.cluster}
                    </.pp_chip>
                  </div>

                  <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-4 2xl:grid-cols-7 gap-2 sm:gap-3">
                    <.stat_tile label="Total VMs" value={m.total_vms} highlight={:neutral} />
                    <.stat_tile label="Running" value={m.running} highlight={:success} />
                    <.stat_tile label="Stopped" value={m.stopped} highlight={:danger} />
                    <.stat_tile
                      label="Guest CPUs (VMIs)"
                      value={m.total_guest_cpu_cores}
                      highlight={:neutral}
                    />
                    <.stat_tile
                      label="Nodes ready"
                      value={"#{m.nodes_ready}/#{m.nodes_total}"}
                      highlight={:neutral}
                    />
                    <.stat_tile label="PVCs" value={m.pvc_total} highlight={:neutral} />
                    <.stat_tile label="Running VMIs" value={m.vmi_running} highlight={:success} />
                  </div>

                  <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-2 sm:gap-3 max-w-6xl">
                    <.usage_cluster_card
                      id="dashboard-usage-cpu"
                      label="Cluster CPU usage"
                      overlay={m.usage_cpu_overlay}
                      value={m.usage_cpu_value}
                      sub={m.usage_cpu_sub}
                      highlight={m.usage_cpu_highlight}
                    />
                    <.usage_cluster_card
                      id="dashboard-usage-mem"
                      label="Cluster memory usage"
                      overlay={m.usage_mem_overlay}
                      value={m.usage_mem_value}
                      sub={m.usage_mem_sub}
                      highlight={m.usage_mem_highlight}
                    />
                    <.dashboard_version_card
                      id="dashboard-version-kubernetes"
                      label="Kubernetes version"
                      value={data.kubernetes_version}
                      hint={version_card_hint(data.kubernetes_version_error)}
                    />
                    <.dashboard_version_card
                      id="dashboard-version-kubevirt"
                      label="KubeVirt version"
                      value={shorten_version_display(data.kubevirt_version)}
                      title={data.kubevirt_version}
                      hint={version_card_hint(data.kubevirt_version_error)}
                    />
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3 md:gap-4 2xl:gap-5 min-w-0">
                    <.apex_chart
                      class="min-w-0"
                      id="chart-vm-status"
                      title="VMs by status"
                      height="200px"
                      opts={DashboardCharts.vm_status_donut(m.running, m.stopped, m.other_vm)}
                    />
                    <.apex_chart
                      class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                      id="chart-vm-per-node"
                      title="VMIs per node"
                      height={"#{m.node_resource_chart_height_px}px"}
                      opts={DashboardCharts.vms_per_node_bar(m.node_labels, m.node_vm_counts)}
                    />
                    <.apex_chart
                      class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                      id="chart-guest-cpu-node"
                      title="Guest CPUs per node (VMIs)"
                      height={"#{m.node_resource_chart_height_px}px"}
                      opts={
                        DashboardCharts.horizontal_bar(
                          "Guest CPUs",
                          m.node_labels,
                          m.node_guest_cpu_totals,
                          "var(--color-primary)"
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                      id="chart-mem-node"
                      title="Memory per node (MiB, guest)"
                      height={"#{m.node_resource_chart_height_px}px"}
                      opts={
                        DashboardCharts.horizontal_bar(
                          "MiB",
                          m.node_labels,
                          m.node_mem_mib,
                          "var(--color-success)"
                        )
                      }
                    />
                    <.apex_chart
                      class="min-w-0"
                      id="chart-nodes-scheduling"
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
                      id="chart-pvc-class"
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
                      id="chart-pvc-status"
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
                    <%= if m.node_load_from_prometheus? do %>
                      <.apex_chart
                        class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                        id="chart-node-load"
                        title="Node CPU by utilization (Prometheus)"
                        height={"#{m.node_load_chart_height_px}px"}
                        opts={
                          DashboardCharts.node_load_placeholder(
                            ["0-25%", "25-50%", "50-75%", "75-100%"],
                            m.node_load_buckets
                          )
                        }
                      />
                    <% else %>
                      <.node_load_chart_placeholder id="node-load-chart-placeholder" />
                    <% end %>
                    <.apex_chart
                      class="min-w-0"
                      id="chart-health"
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
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="vms" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-computer-desktop" class="size-5 text-pp-primary" />
                      Virtual machines
                      <.tab_heading_hint
                        id="dashboard-tab-vms-hint"
                        tip="Each row is a VirtualMachine with live instance fields from the matching VMI (same namespace and name) when it exists."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.vmi_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list VMIs — join columns will be empty ({vm_error_text(
                          data.vmi_error
                        )}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <div class="mt-1">
                      <.virtual_machines_table
                        items={data.vms}
                        vmis={if(data.vmi_error, do: [], else: data.vmis)}
                        pvcs={List.wrap(data.pvcs)}
                        virt_launcher_pods={List.wrap(data.virt_launcher_pods)}
                        pod_metrics={List.wrap(data.pod_metrics)}
                        filters={@filters["vms"]}
                        sort={@sort["vms"]}
                        empty_label="No VirtualMachines found."
                        id_prefix="vm"
                      />
                    </div>
                  <% end %>
                  <%= if data.vmi_error == nil && data.vm_error == nil do %>
                    <% orphans = vmi_orphans_without_vm(data.vms, data.vmis) %>
                    <div :if={orphans != []} class="space-y-2 pt-2 border-t border-base-300/50">
                      <h3 class="text-base font-medium flex items-center gap-2">
                        <.icon name="hero-cpu-chip" class="size-5 text-secondary" />
                        VM instances without a VirtualMachine
                        <.tab_heading_hint
                          id="dashboard-tab-orphan-vmi-hint"
                          tip="Usually short-lived (for example during delete); same columns as the main instance view."
                        />
                      </h3>
                      <.orphan_virtual_machine_instance_table items={orphans} id_prefix="orphan-vmi" />
                    </div>
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:networks}
                active={@active_tab}
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="vm-networks" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-wifi" class="size-5 text-pp-primary" /> VM network interfaces
                      <.tab_heading_hint
                        id="dashboard-tab-networks-hint"
                        tip="Declared on each VirtualMachine template (spec.template.spec.domain.devices.interfaces), with live MAC, IP, and guest interface name from the matching VMI when running."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_network_interfaces_table
                      vms={data.vms}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
                      filters={@filters["networks"]}
                      sort={@sort["networks"]}
                      id_prefix="vm-net"
                    />
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:disks}
                active={@active_tab}
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="vm-disks" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-circle-stack" class="size-5 text-pp-primary" />
                      VM disks &amp; volumes
                      <.tab_heading_hint
                        id="dashboard-tab-disks-hint"
                        tip="Block devices from spec.template.spec.domain.devices.disks linked to template volumes; size and storage class use DataVolume templates and cluster PVCs when resolvable."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_disks_detail_table
                      vms={data.vms}
                      pvcs={List.wrap(data.pvcs)}
                      filters={@filters["disks"]}
                      sort={@sort["disks"]}
                      id_prefix="vm-disk"
                    />
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:storage_classes}
                active={@active_tab}
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="cluster-storage-classes" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-archive-box" class="size-5 text-pp-primary" /> Storage classes
                      <.tab_heading_hint
                        id="dashboard-tab-storage-classes-hint"
                        tip="Cluster-scoped StorageClass objects from storage.k8s.io/v1. PVC counts use spec.storageClassName from all namespaces; PVCs with no class set are listed separately. Names on PVCs that do not match any listed class may be typos or removed classes."
                      />
                    </h2>
                  </div>
                  <%= if data.storage_class_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list StorageClasses ({vm_error_text(data.storage_class_error)}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.storage_class_error == nil do %>
                    <.storage_classes_table
                      storage_classes={List.wrap(data.storage_classes)}
                      pvcs={List.wrap(data.pvcs)}
                      filters={@filters["storage_classes"]}
                      sort={@sort["storage_classes"]}
                      id_prefix="storage-class"
                    />
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:nodes}
                active={@active_tab}
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="cluster-nodes" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-server-stack" class="size-5 text-pp-primary" /> Nodes
                      <.tab_heading_hint
                        id="dashboard-tab-nodes-hint"
                        tip="Kubernetes Nodes from the cluster API (status.addresses, allocatable resources, conditions). CPU and memory % prefer metrics-server NodeMetrics; when that API is missing, values are taken from Prometheus node_exporter (same queries as the dashboard) when scrape targets match the node name, hostname, or internal IP. VMIs counts use VMI status.nodeName."
                      />
                    </h2>
                  </div>
                  <%= if data.node_error do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        Could not list Nodes ({vm_error_text(data.node_error)}).
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.metrics_error && not m.prometheus_ok? do %>
                    <.pp_alert severity="warning" class="text-sm">
                      <span>
                        metrics-server NodeMetrics is unavailable ({vm_error_text(data.metrics_error)}). {cluster_usage_prometheus_hint_text()}
                      </span>
                    </.pp_alert>
                  <% end %>
                  <%= if data.node_error == nil do %>
                    <.nodes_table
                      nodes={List.wrap(data.nodes)}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
                      node_metrics={List.wrap(data.node_metrics)}
                      prometheus_node_detail={m.prometheus_node_detail}
                      filters={@filters["nodes"]}
                      sort={@sort["nodes"]}
                      id_prefix="node"
                    />
                  <% end %>
                </section>
              </.tab_panel>

              <.tab_panel
                root_id="kubevirt-dashboard-tabs"
                tab={:vm_topology}
                active={@active_tab}
                class="scroll-mt-24 pt-1 min-w-0 space-y-3"
              >
                <div>
                  <h2 class="text-lg font-medium flex items-center gap-2">
                    <.icon name="hero-squares-2x2" class="size-5 text-pp-primary" /> Topology
                    <.tab_heading_hint
                      id="dashboard-tab-topology-hint"
                      tip="VMs are linked to cluster nodes using each VMI status.nodeName (matching VM and VMI name and namespace). Stopped VMs without a VMI appear under Unscheduled."
                    />
                  </h2>
                </div>
                <section
                  id="vm-topology-root"
                  data-vm-topology-root
                  class="rounded-xl border border-base-300/60 bg-base-200/30 overflow-hidden"
                  phx-hook="VmTopology"
                  data-topology={Jason.encode!(VmTopology.build(data))}
                >
                  <div class="flex flex-col xl:flex-row min-h-[min(78vh,820px)] max-h-[min(85vh,900px)]">
                    <aside class="w-full xl:w-64 shrink-0 border-b xl:border-b-0 xl:border-r border-base-300/50 p-4 space-y-5 bg-base-200/40">
                      <div>
                        <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50 mb-2">
                          Legend
                        </p>
                        <ul class="text-xs space-y-1.5 text-base-content/80">
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-sm bg-primary/85 border border-primary shrink-0 shadow-sm" />
                            Cluster node (ready)
                          </li>
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-sm bg-warning/85 border border-warning shrink-0 shadow-sm" />
                            Node cordoned
                          </li>
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-sm bg-stopped-dim border border-stopped shrink-0 shadow-sm" />
                            Node not ready, unknown node, or Unscheduled
                          </li>
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-full bg-success/85 border border-success shrink-0 shadow-sm" />
                            VM running
                          </li>
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-full bg-stopped-dim border border-stopped shrink-0 shadow-sm" />
                            VM stopped
                          </li>
                          <li class="flex items-center gap-2">
                            <span class="size-3 rounded-full bg-warning/70 border border-warning shrink-0 shadow-sm" />
                            VM other
                          </li>
                        </ul>
                      </div>
                      <div>
                        <label
                          for="vm-topology-layout"
                          class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50 block mb-1.5 text-center"
                        >
                          Layout
                        </label>
                        <%!-- DaisyUI .select styles inner `select` via `.select select`; wrapper fixes vertical alignment. --%>
                        <div class={[
                          "select select-primary select-bordered select-sm w-full",
                          "transition-colors duration-200"
                        ]}>
                          <select
                            id="vm-topology-layout"
                            data-topology-layout
                            class="w-full text-center text-sm font-medium"
                          >
                            <option value="organic">Organic</option>
                            <option value="hierarchical">Hierarchical</option>
                          </select>
                        </div>
                      </div>
                      <div>
                        <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50 mb-2">
                          Actions
                        </p>
                        <div class="flex flex-wrap gap-2">
                          <button
                            type="button"
                            data-topology-reset
                            id="vm-topology-reset"
                            class="btn btn-ghost btn-sm"
                          >
                            Reset view
                          </button>
                          <button
                            type="button"
                            data-topology-fit
                            id="vm-topology-fit"
                            class="btn btn-outline btn-primary btn-sm"
                          >
                            Fit to screen
                          </button>
                        </div>
                      </div>
                      <div>
                        <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50 mb-2">
                          Summary
                        </p>
                        <dl class="text-xs space-y-1 text-base-content/85">
                          <div class="flex justify-between gap-2">
                            <dt class="text-base-content/55">Nodes</dt>
                            <dd class="font-mono tabular-nums" data-topology-summary-nodes>—</dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-base-content/55">VMs</dt>
                            <dd class="font-mono tabular-nums" data-topology-summary-vms>—</dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-base-content/55">Running</dt>
                            <dd
                              class="font-mono tabular-nums text-success"
                              data-topology-summary-running
                            >
                              —
                            </dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-base-content/55">Stopped</dt>
                            <dd
                              class="font-mono tabular-nums text-stopped"
                              data-topology-summary-stopped
                            >
                              —
                            </dd>
                          </div>
                        </dl>
                      </div>
                    </aside>
                    <div class="flex-1 min-h-[min(52vh,560px)] min-w-0 bg-base-300/20 relative">
                      <div
                        id="vm-topology-canvas"
                        data-topology-canvas
                        class="absolute inset-0 w-full h-full min-h-[min(52vh,560px)]"
                      >
                      </div>
                    </div>
                  </div>
                </section>
              </.tab_panel>
            </div>
          </.async_result>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :tip, :string,
    required: true,
    doc: "Shown on hover (title) and for screen readers (aria-label)"

  attr :id, :string, default: nil

  defp tab_heading_hint(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "inline-flex shrink-0 rounded-full p-0.5 -m-0.5",
        "text-base-content/45 hover:text-primary cursor-help",
        "outline-none transition-colors duration-200",
        "focus-visible:ring-2 focus-visible:ring-primary/45 focus-visible:ring-offset-2",
        "focus-visible:ring-offset-base-100"
      ]}
      tabindex="0"
      aria-label={@tip}
      title={@tip}
    >
      <.icon name="hero-information-circle" class="size-5" />
    </span>
    """
  end

  attr :tab, :string, required: true
  attr :filters, :map, required: true
  attr :search_placeholder, :string, default: "Search by name…"

  attr :specs, :list,
    required: true,
    doc: "[%{field: \"phase\", label: \"Phase\", options: [\"Running\", ...]}, ...]"

  defp table_filter_bar(assigns) do
    active? = Enum.any?(assigns.filters, fn {_k, v} -> v != "" end)
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <div class="flex flex-wrap items-center gap-x-5 gap-y-2 py-2.5">
      <div class="flex items-center gap-2">
        <.icon name="hero-magnifying-glass" class="size-4 text-pp-on-surface/40" />
        <input
          type="text"
          value={Map.get(@filters, "search", "")}
          placeholder={@search_placeholder}
          phx-keyup="set_filter"
          phx-value-tab={@tab}
          phx-value-field="search"
          phx-debounce="300"
          name="value"
          class="w-44 rounded-sm border border-pp-outline bg-pp-surface px-2 py-1 text-xs text-pp-on-surface outline-none focus:border-pp-primary"
        />
      </div>
      <form
        :for={spec <- @specs}
        id={"filter-form-#{@tab}-#{spec.field}"}
        class="flex items-center gap-2"
        phx-change="set_filter"
      >
        <label class="text-xs text-pp-on-surface/55 whitespace-nowrap">{spec.label}</label>
        <input type="hidden" name="tab" value={@tab} />
        <input type="hidden" name="field" value={spec.field} />
        <select
          class="rounded-sm border border-pp-outline bg-pp-surface px-2 py-1 text-xs text-pp-on-surface outline-none focus:border-pp-primary"
          name="value"
        >
          <option value="" selected={Map.get(@filters, spec.field, "") == ""}>All</option>
          <option
            :for={opt <- spec.options}
            value={opt}
            selected={Map.get(@filters, spec.field, "") == opt}
          >
            {opt}
          </option>
        </select>
      </form>
      <.pp_button
        :if={@active?}
        variant="text"
        phx-click="clear_filters"
        phx-value-tab={@tab}
        class="text-xs px-3 py-1"
      >
        Clear filters
      </.pp_button>
    </div>
    """
  end

  attr :tab, :string, required: true
  attr :field, :string, required: true
  attr :sort, :any, default: nil
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp sortable_th(assigns) do
    direction =
      case assigns.sort do
        {field, dir} when field == assigns.field -> dir
        _ -> nil
      end

    assigns = assign(assigns, :direction, direction && to_string(direction))

    ~H"""
    <.pp_table_cell
      variant="head"
      sortable
      sort_direction={@direction}
      class={@class}
      title={@title}
      phx-click="sort"
      phx-value-tab={@tab}
      phx-value-field={@field}
    >
      {render_slot(@inner_block)}
    </.pp_table_cell>
    """
  end

  defp sort_rows(rows, nil, _field_funs), do: rows

  defp sort_rows(rows, {field, dir}, field_funs) do
    case Map.fetch(field_funs, field) do
      {:ok, fun} -> Enum.sort_by(rows, fun, dir)
      :error -> rows
    end
  end

  # Node CPU/Mem % are pre-formatted strings like "45%" or "—" (unavailable).
  # Parse the leading integer for a numeric sort; unavailable sorts lowest.
  defp pct_sort_value(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _rest} -> n
      :error -> -1
    end
  end

  defp pct_sort_value(_), do: -1

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil

  attr :highlight, :atom,
    values: [:neutral, :primary, :success, :danger, :warning],
    default: :neutral

  defp stat_tile(assigns) do
    value_class =
      case assigns.highlight do
        :primary -> "text-pp-primary"
        :success -> "text-emerald-400"
        :danger -> "text-stopped"
        :warning -> "text-amber-400"
        :neutral -> "text-base-content"
      end

    assigns = assign(assigns, :value_class, value_class)

    ~H"""
    <.pp_paper
      elevation={1}
      class="border border-pp-outline/15 px-4 py-3 transition hover:border-pp-primary/30"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-pp-on-surface/50">
        {@label}
      </p>
      <p class={["text-xl font-semibold tabular-nums mt-1", @value_class]}>{@value}</p>
      <p :if={@sub} class="text-xs text-pp-on-surface/45 mt-0.5">{@sub}</p>
    </.pp_paper>
    """
  end

  attr :connected?, :boolean, required: true
  attr :url, :string, required: true

  defp prometheus_compact_indicator(assigns) do
    ~H"""
    <div
      class="inline-flex items-center gap-2 text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50"
      title={@url}
    >
      <span>Prometheus</span>
      <%= if @connected? do %>
        <%!-- DaisyUI status dot + Tailwind ping halo (status styles can mute ping on the same node) --%>
        <div class="relative flex h-3 w-3 shrink-0 items-center justify-center" aria-hidden="true">
          <span class="absolute h-2.5 w-2.5 rounded-full bg-success/55 motion-safe:animate-ping">
          </span>
          <div class="relative z-[1] status status-success"></div>
        </div>
      <% else %>
        <div class="status status-warning shrink-0" aria-hidden="true"></div>
      <% end %>
      <span class="sr-only">
        {if @connected?, do: "reachable", else: "not reachable"}
      </span>
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :overlay, :string, default: nil
  attr :value, :any, required: true
  attr :sub, :string, default: nil

  attr :highlight, :atom,
    values: [:neutral, :primary, :success, :danger, :warning],
    default: :neutral

  defp usage_cluster_card(assigns) do
    value_class =
      case assigns.highlight do
        :primary -> "text-pp-primary"
        :success -> "text-emerald-400"
        :danger -> "text-stopped"
        :warning -> "text-amber-400"
        :neutral -> "text-base-content"
      end

    assigns = assign(assigns, :value_class, value_class)

    ~H"""
    <%= if @overlay do %>
      <section
        id={@id}
        class={[
          "rounded-lg border border-dashed border-warning/45 bg-base-100/35 shadow-sm",
          "p-3 min-w-0 w-full overflow-hidden flex flex-col gap-1.5"
        ]}
      >
        <h3 class="text-xs font-semibold uppercase tracking-wide text-base-content/65 shrink-0 leading-tight">
          {@label}
        </h3>
        <div class="relative w-full min-w-0 shrink-0 rounded-md overflow-hidden border border-base-300/40 bg-base-200/20">
          <div class="h-[168px] w-full relative">
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
                    Prometheus not detected!
                  </p>
                  <p class="mt-1.5 text-warning-content/95">{@overlay}</p>
                </div>
              </div>
            </div>
            <div class="absolute inset-0 flex flex-col justify-center gap-3 px-3 py-3 pointer-events-none opacity-[0.22]">
              <div class="flex items-center gap-2">
                <div class="skeleton h-2.5 w-11 shrink-0"></div>
                <div class="skeleton h-6 flex-1 rounded max-w-[88%]"></div>
              </div>
              <div class="flex items-center gap-2">
                <div class="skeleton h-2.5 w-11 shrink-0"></div>
                <div class="skeleton h-6 flex-1 rounded max-w-[52%]"></div>
              </div>
              <div class="flex items-center gap-2">
                <div class="skeleton h-2.5 w-11 shrink-0"></div>
                <div class="skeleton h-6 flex-1 rounded max-w-[72%]"></div>
              </div>
            </div>
          </div>
        </div>
      </section>
    <% else %>
      <.pp_paper
        id={@id}
        elevation={1}
        class="border border-pp-outline/15 px-4 py-3 transition hover:border-pp-primary/30"
      >
        <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-pp-on-surface/50">
          {@label}
        </p>
        <p class={["text-xl font-semibold tabular-nums mt-1", @value_class]}>{@value}</p>
        <p :if={@sub} class="text-xs text-pp-on-surface/45 mt-0.5">{@sub}</p>
      </.pp_paper>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :title, :string, default: nil
  attr :hint, :string, default: nil

  defp dashboard_version_card(assigns) do
    ~H"""
    <.pp_paper
      id={@id}
      elevation={1}
      class="border border-pp-outline/15 px-4 py-3 min-w-0 w-full transition hover:border-pp-primary/30"
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-pp-on-surface/50">
        {@label}
      </p>
      <p
        class="text-xl font-semibold tabular-nums mt-1 text-pp-on-surface break-words leading-snug"
        title={@title}
      >
        {@value}
      </p>
      <p :if={@hint} class="text-xs text-pp-on-surface/55 mt-1.5 leading-snug">{@hint}</p>
    </.pp_paper>
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
                  Prometheus not detected!
                </p>
                <p class="mt-1.5 text-warning-content/95">
                  {cluster_usage_prometheus_hint_text()}
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

  defp cluster_usage_prometheus_hint_text, do: @cluster_usage_prometheus_hint

  attr :items, :list, required: true
  attr :vmis, :list, default: []
  attr :pvcs, :list, default: []
  attr :virt_launcher_pods, :list, default: []
  attr :pod_metrics, :list, default: []
  attr :filters, :map, default: %{}
  attr :sort, :any, default: nil
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp virtual_machines_table(assigns) do
    all_rows =
      virtual_machines_table_rows(
        assigns.items,
        List.wrap(assigns.vmis),
        List.wrap(assigns.virt_launcher_pods),
        List.wrap(assigns.pod_metrics)
      )

    filters = assigns.filters

    rows =
      all_rows
      |> Enum.filter(&vm_row_matches_filters?(&1, filters))
      |> sort_rows(assigns.sort, %{
        "name" => & &1.name,
        "phase" => & &1.phase,
        "cpu" => &(&1.cpu_pct || -1),
        "memory" => &(&1.mem_pct || -1),
        "node" => & &1.node,
        "ip" => & &1.ip,
        "agent" => & &1.agent_connected?,
        "os" => & &1.os,
        "created" => & &1.created
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(
        :filter_specs,
        [
          %{field: "phase", label: "Phase", options: distinct_present(all_rows, & &1.phase)},
          %{field: "node", label: "Node", options: distinct_present(all_rows, & &1.node)},
          %{field: "agent", label: "Agent", options: ["Running", "Not running"]},
          %{field: "os", label: "OS", options: distinct_present(all_rows, & &1.os)}
        ]
      )

    ~H"""
    <div class="space-y-2">
      <.table_filter_bar
        tab="vms"
        filters={@filters}
        specs={@filter_specs}
        search_placeholder="Search by name or IP…"
      />
      <.pp_table_container>
        <.pp_table dense>
          <.pp_table_head>
            <tr>
              <.sortable_th tab="vms" field="name" sort={@sort}>Name</.sortable_th>
              <.sortable_th tab="vms" field="phase" sort={@sort}>Phase</.sortable_th>
              <.sortable_th
                tab="vms"
                field="cpu"
                sort={@sort}
                title="Used / configured — used comes from metrics-server on the virt-launcher pod"
              >
                CPU
              </.sortable_th>
              <.sortable_th
                tab="vms"
                field="memory"
                sort={@sort}
                title="Used / configured — used comes from metrics-server on the virt-launcher pod"
              >
                Memory
              </.sortable_th>
              <.sortable_th tab="vms" field="node" sort={@sort}>Node</.sortable_th>
              <.sortable_th tab="vms" field="ip" sort={@sort}>IP</.sortable_th>
              <.sortable_th tab="vms" field="agent" sort={@sort} title="QEMU guest agent connected">
                Agent
              </.sortable_th>
              <.sortable_th
                tab="vms"
                field="os"
                sort={@sort}
                title="Guest-reported OS (qemu-guest-agent)"
              >
                OS
              </.sortable_th>
              <.sortable_th tab="vms" field="created" sort={@sort}>Created</.sortable_th>
            </tr>
          </.pp_table_head>
          <.pp_table_body>
            <tr :if={@rows == []}>
              <td colspan="9" class="text-center text-base-content/50 py-8">
                {if(@items == [], do: @empty_label, else: "No VMs match the current filters.")}
              </td>
            </tr>
            <%= for {row, i} <- Enum.with_index(@rows) do %>
              <tr
                id={"#{@id_prefix}-row-#{i}"}
                class="hover:bg-base-200/40 transition-colors cursor-pointer"
                phx-click={JS.navigate(~p"/vms/#{row.namespace}/#{row.name}")}
              >
                <td class="whitespace-nowrap">
                  <div class="font-medium">{row.name}</div>
                  <div class="font-mono text-xs text-base-content/60">{row.namespace}</div>
                </td>
                <td>
                  <span class={row.phase_badge_classes}>{row.phase}</span>
                </td>
                <td
                  class="text-xs tabular-nums font-medium"
                  title={
                    if(row.usage_unavailable?,
                      do: "Usage unavailable — no metrics-server data for this VM's pod yet",
                      else: "sockets × cores × threads"
                    )
                  }
                >
                  {row.cpu_display}
                  <span :if={row.cpu_pct} class={["ml-1", usage_pct_color_class(row.cpu_pct)]}>
                    {row.cpu_pct}%
                  </span>
                </td>
                <td
                  class="text-xs font-mono text-base-content/75"
                  title={
                    if(row.usage_unavailable?,
                      do: "Usage unavailable — no metrics-server data for this VM's pod yet",
                      else: nil
                    )
                  }
                >
                  {row.mem_display}
                  <span :if={row.mem_pct} class={["ml-1", usage_pct_color_class(row.mem_pct)]}>
                    {row.mem_pct}%
                  </span>
                </td>
                <td
                  class="font-mono text-xs text-base-content/70 max-w-[10rem] truncate"
                  title={row.node}
                >
                  {row.node}
                </td>
                <td
                  class="font-mono text-xs text-base-content/80 max-w-[9rem] truncate"
                  title={row.ip}
                >
                  {row.ip}
                </td>
                <td>
                  <span :if={row.agent_connected?} class="text-xs font-medium text-pp-primary">
                    Running
                  </span>
                  <span :if={!row.agent_connected?} class="text-xs font-medium text-stopped">
                    Not running
                  </span>
                </td>
                <td class="text-xs text-base-content/80 max-w-[10rem] truncate" title={row.os}>
                  {row.os}
                </td>
                <td class="text-xs text-base-content/60 whitespace-nowrap">{row.created}</td>
              </tr>
            <% end %>
          </.pp_table_body>
        </.pp_table>
      </.pp_table_container>
    </div>
    """
  end

  defp vm_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], [row.name, row.ip]) and
      matches_field?(filters["phase"], row.phase) and
      matches_field?(filters["node"], row.node) and
      matches_field?(
        filters["agent"],
        if(row.agent_connected?, do: "Running", else: "Not running")
      ) and
      matches_field?(filters["os"], row.os)
  end

  defp matches_field?("", _value), do: true
  defp matches_field?(filter, value), do: filter == value

  defp matches_search?(nil, _values), do: true
  defp matches_search?("", _values), do: true

  defp matches_search?(term, values) when is_list(values) do
    downcased = String.downcase(term)
    Enum.any?(values, &String.contains?(String.downcase(to_string(&1)), downcased))
  end

  defp matches_search?(term, value), do: matches_search?(term, [value])

  defp distinct_present(rows, fun) do
    rows
    |> Enum.map(fun)
    |> Enum.reject(&(&1 in [nil, "", "—"]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  attr :items, :list, required: true
  attr :id_prefix, :string, required: true

  defp orphan_virtual_machine_instance_table(assigns) do
    ~H"""
    <.pp_table_container>
      <.pp_table dense>
        <.pp_table_head>
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>Phase</th>
            <th>Node</th>
            <th>CPU (guest)</th>
            <th>Memory</th>
            <th>IP</th>
            <th>Ready</th>
            <th>Created</th>
          </tr>
        </.pp_table_head>
        <.pp_table_body>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs whitespace-nowrap">{vm_meta(item, :namespace)}</td>
              <td class="font-medium whitespace-nowrap">{vm_meta(item, :name)}</td>
              <td>
                <.pp_chip size="small" variant="outlined">{vmi_phase(item)}</.pp_chip>
              </td>
              <td
                class="font-mono text-xs text-base-content/70 max-w-[10rem] truncate"
                title={vmi_scheduling_node_name(item)}
              >
                {vmi_scheduling_node_name(item)}
              </td>
              <td class="text-xs tabular-nums">{vmi_spec_cpu_cores(item)}</td>
              <td class="text-xs font-mono text-base-content/75">{vmi_spec_memory_guest(item)}</td>
              <td
                class="font-mono text-xs text-base-content/80 max-w-[9rem] truncate"
                title={vmi_primary_ip(item)}
              >
                {vmi_primary_ip(item)}
              </td>
              <td class="text-xs">{vmi_ready_label(item)}</td>
              <td class="text-xs text-base-content/60 whitespace-nowrap">
                {vm_meta(item, :created)}
              </td>
            </tr>
          <% end %>
        </.pp_table_body>
      </.pp_table>
    </.pp_table_container>
    """
  end

  attr :vms, :list, required: true
  attr :vmis, :list, default: []
  attr :filters, :map, default: %{}
  attr :sort, :any, default: nil
  attr :id_prefix, :string, required: true

  defp virtual_machine_network_interfaces_table(assigns) do
    all_rows = virtual_machine_network_interface_rows(assigns.vms, List.wrap(assigns.vmis))
    filters = assigns.filters

    rows =
      all_rows
      |> Enum.filter(&network_row_matches_filters?(&1, filters))
      |> sort_rows(assigns.sort, %{
        "vm" => & &1.vm_name,
        "interface" => & &1.iface_name,
        "binding" => & &1.binding,
        "ips" => & &1.ips,
        "vmi_phase" => & &1.vmi_phase
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:all_rows_empty?, all_rows == [])
      |> assign(
        :filter_specs,
        [
          %{
            field: "binding",
            label: "Binding",
            options: distinct_present(all_rows, & &1.binding)
          },
          %{
            field: "vmi_phase",
            label: "VMI phase",
            options: distinct_present(all_rows, & &1.vmi_phase)
          }
        ]
      )

    ~H"""
    <div class="space-y-2">
      <.table_filter_bar
        tab="networks"
        filters={@filters}
        specs={@filter_specs}
        search_placeholder="Search by VM name or IP…"
      />
      <.pp_table_container>
        <.pp_table dense>
          <.pp_table_head>
            <tr>
              <.sortable_th tab="networks" field="vm" sort={@sort}>VM</.sortable_th>
              <.sortable_th tab="networks" field="interface" sort={@sort}>Interface</.sortable_th>
              <.sortable_th tab="networks" field="binding" sort={@sort}>Binding</.sortable_th>
              <.sortable_th tab="networks" field="ips" sort={@sort}>IP addresses</.sortable_th>
              <.sortable_th tab="networks" field="vmi_phase" sort={@sort}>VMI phase</.sortable_th>
            </tr>
          </.pp_table_head>
          <.pp_table_body>
            <tr :if={@rows == []}>
              <td colspan="5" class="text-center text-base-content/50 py-8">
                {if(@all_rows_empty?,
                  do: "No network interfaces defined on any VirtualMachine.",
                  else: "No interfaces match the current filters."
                )}
              </td>
            </tr>
            <%= for {row, i} <- Enum.with_index(@rows) do %>
              <tr
                id={"#{@id_prefix}-row-#{i}"}
                class="hover:bg-base-200/40 transition-colors cursor-pointer"
                phx-click={
                  JS.navigate(~p"/networks/#{row.namespace}/#{row.vm_name}/#{row.iface_name}")
                }
              >
                <td class="whitespace-nowrap">
                  <div class="font-medium">{row.vm_name}</div>
                  <div class="font-mono text-xs text-base-content/60">{row.namespace}</div>
                </td>
                <td class="text-xs font-mono text-base-content/80">{row.iface_name}</td>
                <td class="text-xs whitespace-nowrap">{row.binding}</td>
                <td
                  class="font-mono text-xs text-base-content/80 max-w-[14rem] truncate"
                  title={row.ips}
                >
                  {row.ips}
                </td>
                <td>
                  <.pp_chip size="small">{row.vmi_phase}</.pp_chip>
                </td>
              </tr>
            <% end %>
          </.pp_table_body>
        </.pp_table>
      </.pp_table_container>
    </div>
    """
  end

  defp network_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], [row.vm_name, row.ips]) and
      matches_field?(filters["binding"], row.binding) and
      matches_field?(filters["vmi_phase"], row.vmi_phase)
  end

  attr :vms, :list, required: true
  attr :pvcs, :list, default: []
  attr :filters, :map, default: %{}
  attr :sort, :any, default: nil
  attr :id_prefix, :string, required: true

  defp virtual_machine_disks_detail_table(assigns) do
    all_rows = virtual_machine_disk_detail_rows(assigns.vms, List.wrap(assigns.pvcs))
    filters = assigns.filters

    rows =
      all_rows
      |> Enum.filter(&disk_row_matches_filters?(&1, filters))
      |> sort_rows(assigns.sort, %{
        "vm" => & &1.vm_name,
        "disk" => & &1.disk_name,
        "volume_kind" => & &1.volume_kind,
        "size" => & &1.size_gib,
        "storage_class" => & &1.storage_class,
        "pvc_phase" => & &1.pvc_phase
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:all_rows_empty?, all_rows == [])
      |> assign(
        :filter_specs,
        [
          %{
            field: "volume_kind",
            label: "Volume kind",
            options: distinct_present(all_rows, & &1.volume_kind)
          },
          %{
            field: "storage_class",
            label: "Storage class",
            options: distinct_present(all_rows, & &1.storage_class)
          },
          %{
            field: "pvc_phase",
            label: "PVC phase",
            options: distinct_present(all_rows, & &1.pvc_phase)
          }
        ]
      )

    ~H"""
    <div class="space-y-2">
      <.table_filter_bar tab="disks" filters={@filters} specs={@filter_specs} />
      <.pp_table_container>
        <.pp_table dense>
          <.pp_table_head>
            <tr>
              <.sortable_th tab="disks" field="vm" sort={@sort}>VM</.sortable_th>
              <.sortable_th tab="disks" field="disk" sort={@sort}>Disk</.sortable_th>
              <.sortable_th tab="disks" field="volume_kind" sort={@sort}>Volume kind</.sortable_th>
              <.sortable_th tab="disks" field="size" sort={@sort}>Size</.sortable_th>
              <.sortable_th tab="disks" field="storage_class" sort={@sort}>
                Storage class
              </.sortable_th>
              <.sortable_th tab="disks" field="pvc_phase" sort={@sort}>PVC phase</.sortable_th>
            </tr>
          </.pp_table_head>
          <.pp_table_body>
            <tr :if={@rows == []}>
              <td colspan="6" class="text-center text-base-content/50 py-8">
                {if(@all_rows_empty?,
                  do: "No disks defined on any VirtualMachine.",
                  else: "No disks match the current filters."
                )}
              </td>
            </tr>
            <%= for {row, i} <- Enum.with_index(@rows) do %>
              <tr
                id={"#{@id_prefix}-row-#{i}"}
                class="hover:bg-base-200/40 transition-colors cursor-pointer"
                phx-click={JS.navigate(~p"/disks/#{row.namespace}/#{row.vm_name}/#{row.disk_name}")}
              >
                <td class="whitespace-nowrap">
                  <div class="font-medium">{row.vm_name}</div>
                  <div class="font-mono text-xs text-base-content/60">{row.namespace}</div>
                </td>
                <td class="text-xs font-mono text-base-content/80">{row.disk_name}</td>
                <td class="text-xs whitespace-nowrap">{row.volume_kind}</td>
                <td class="text-xs tabular-nums whitespace-nowrap">{row.size}</td>
                <td class="text-xs max-w-[8rem] truncate" title={row.storage_class}>
                  {row.storage_class}
                </td>
                <td class="text-xs">{row.pvc_phase}</td>
              </tr>
            <% end %>
          </.pp_table_body>
        </.pp_table>
      </.pp_table_container>
    </div>
    """
  end

  defp disk_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], row.vm_name) and
      matches_field?(filters["volume_kind"], row.volume_kind) and
      matches_field?(filters["storage_class"], row.storage_class) and
      matches_field?(filters["pvc_phase"], row.pvc_phase)
  end

  attr :storage_classes, :list, required: true
  attr :pvcs, :list, required: true
  attr :filters, :map, default: %{}
  attr :sort, :any, default: nil
  attr :id_prefix, :string, required: true

  defp storage_classes_table(assigns) do
    pvc_by_class = pvc_counts_by_storage_class_name(assigns.pvcs)
    sc_names = storage_class_name_set(assigns.storage_classes)
    all_rows = storage_classes_table_rows(assigns.storage_classes, pvc_by_class)
    orphan_refs = orphan_storage_class_refs_with_counts(pvc_by_class, sc_names)
    unset_count = Map.get(pvc_by_class, "", 0)

    filters = assigns.filters

    rows =
      all_rows
      |> Enum.filter(&storage_class_row_matches_filters?(&1, filters))
      |> sort_rows(assigns.sort, %{
        "name" => & &1.name,
        "default" => & &1.default?,
        "provisioner" => & &1.provisioner,
        "pvcs" => & &1.pvc_count
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:all_rows_empty?, all_rows == [])
      |> assign(:orphan_refs, orphan_refs)
      |> assign(:unset_count, unset_count)
      |> assign(
        :filter_specs,
        [
          %{
            field: "provisioner",
            label: "Provisioner",
            options: distinct_present(all_rows, & &1.provisioner)
          }
        ]
      )

    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content/70 mb-2">
      <span>
        <span class="font-semibold text-base-content/85 tabular-nums">
          {length(@storage_classes)}
        </span>
        storage class{if length(@storage_classes) == 1, do: "", else: "es"}
      </span>
      <span :if={@unset_count > 0}>
        <span class="font-semibold text-base-content/85 tabular-nums">{@unset_count}</span>
        PVC{if @unset_count == 1, do: "", else: "s"} with no storageClassName
      </span>
    </div>
    <div class="space-y-2">
      <.table_filter_bar tab="storage_classes" filters={@filters} specs={@filter_specs} />
      <.pp_table_container>
        <.pp_table dense>
          <.pp_table_head>
            <tr>
              <.sortable_th tab="storage_classes" field="name" sort={@sort}>Name</.sortable_th>
              <.sortable_th tab="storage_classes" field="default" sort={@sort}>Default</.sortable_th>
              <.sortable_th tab="storage_classes" field="provisioner" sort={@sort}>
                Provisioner
              </.sortable_th>
              <.sortable_th
                tab="storage_classes"
                field="pvcs"
                sort={@sort}
                title="PVCs in the cluster using this storageClassName"
              >
                PVCs
              </.sortable_th>
            </tr>
          </.pp_table_head>
          <.pp_table_body>
            <tr :if={@rows == []}>
              <td colspan="4" class="text-center text-base-content/50 py-8">
                {if(@all_rows_empty?,
                  do: "No StorageClass objects returned from the API.",
                  else: "No storage classes match the current filters."
                )}
              </td>
            </tr>
            <%= for {row, i} <- Enum.with_index(@rows) do %>
              <tr
                id={"#{@id_prefix}-row-#{i}"}
                class="hover:bg-base-200/40 transition-colors cursor-pointer"
                phx-click={JS.navigate(~p"/storage_classes/#{row.name}")}
              >
                <td class="font-mono text-xs font-medium whitespace-nowrap">{row.name}</td>
                <td>
                  <%= if row.default? do %>
                    <.pp_chip size="small" color="primary">default</.pp_chip>
                  <% else %>
                    <span class="text-xs text-base-content/40">—</span>
                  <% end %>
                </td>
                <td
                  class="text-xs font-mono text-base-content/80 max-w-[14rem] truncate"
                  title={row.provisioner}
                >
                  {row.provisioner}
                </td>
                <td class="text-xs tabular-nums font-medium">{row.pvc_count}</td>
              </tr>
            <% end %>
          </.pp_table_body>
        </.pp_table>
      </.pp_table_container>
    </div>
    <div
      :if={@orphan_refs != []}
      class="alert alert-warning text-sm py-3"
      id="dashboard-storage-class-orphan-pvcs"
    >
      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
      <div>
        <p class="font-medium">PVCs reference unknown storage classes</p>
        <p class="text-xs opacity-90 mt-1">
          These names appear on PVCs but do not match any listed StorageClass:
          <span class="font-mono">
            {orphan_storage_class_refs_pretty(@orphan_refs)}
          </span>
        </p>
      </div>
    </div>
    """
  end

  defp storage_class_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], row.name) and
      matches_field?(filters["provisioner"], row.provisioner)
  end

  attr :nodes, :list, required: true
  attr :vmis, :list, default: []
  attr :node_metrics, :list, default: []
  attr :prometheus_node_detail, :map, default: %{}
  attr :filters, :map, default: %{}
  attr :sort, :any, default: nil
  attr :id_prefix, :string, required: true

  defp nodes_table(assigns) do
    merged =
      nodes_merged_usage_map(
        assigns.nodes,
        assigns.node_metrics,
        assigns.prometheus_node_detail || %{}
      )

    all_rows = kubernetes_nodes_table_rows(assigns.nodes, assigns.vmis, merged)
    filters = assigns.filters

    rows =
      all_rows
      |> Enum.filter(&node_row_matches_filters?(&1, filters))
      |> sort_rows(assigns.sort, %{
        "name" => & &1.name,
        "ready" => & &1.is_ready,
        "role" => & &1.role,
        "vmis" => & &1.vmi_count,
        "cpu" => &pct_sort_value(&1.cpu_pct),
        "mem" => &pct_sort_value(&1.mem_pct),
        "os" => & &1.os_image
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:all_rows_empty?, all_rows == [])
      |> assign(
        :filter_specs,
        [
          %{field: "ready", label: "Ready", options: ["Yes", "No"]},
          %{field: "role", label: "Role", options: distinct_present(all_rows, & &1.role)},
          %{field: "os", label: "OS", options: distinct_present(all_rows, & &1.os_image)}
        ]
      )

    ~H"""
    <div class="space-y-2">
      <.table_filter_bar tab="nodes" filters={@filters} specs={@filter_specs} />
      <.pp_table_container>
        <.pp_table dense>
          <.pp_table_head>
            <tr>
              <.sortable_th tab="nodes" field="name" sort={@sort}>Name</.sortable_th>
              <.sortable_th tab="nodes" field="ready" sort={@sort}>Ready</.sortable_th>
              <.sortable_th tab="nodes" field="role" sort={@sort}>Role</.sortable_th>
              <.sortable_th tab="nodes" field="os" sort={@sort}>OS</.sortable_th>
              <.sortable_th tab="nodes" field="vmis" sort={@sort}>VMIs</.sortable_th>
              <.sortable_th
                tab="nodes"
                field="cpu"
                sort={@sort}
                title="metrics-server (usage / allocatable) when available; else Prometheus node_exporter per target"
              >
                CPU %
              </.sortable_th>
              <.sortable_th
                tab="nodes"
                field="mem"
                sort={@sort}
                title="metrics-server (usage / allocatable) when available; else Prometheus node_exporter per target"
              >
                Mem %
              </.sortable_th>
            </tr>
          </.pp_table_head>
          <.pp_table_body>
            <tr :if={@rows == []}>
              <td colspan="7" class="text-center text-base-content/50 py-8">
                {if(@all_rows_empty?,
                  do: "No nodes returned from the API.",
                  else: "No nodes match the current filters."
                )}
              </td>
            </tr>
            <%= for {row, i} <- Enum.with_index(@rows) do %>
              <tr
                id={"#{@id_prefix}-row-#{i}"}
                class="hover:bg-base-200/40 transition-colors cursor-pointer"
                title={row.scheduling_hint}
                phx-click={JS.navigate(~p"/nodes/#{row.name}")}
              >
                <td class="font-mono text-xs font-medium whitespace-nowrap">{row.name}</td>
                <td>
                  <%= if row.is_ready do %>
                    <.pp_chip size="small" color="success">Yes</.pp_chip>
                  <% else %>
                    <.pp_chip size="small" color="error">No</.pp_chip>
                  <% end %>
                </td>
                <td>
                  <.pp_chip size="small" class="font-mono text-[0.7rem]">{row.role}</.pp_chip>
                </td>
                <td class="text-xs text-base-content/80 max-w-[12rem] truncate" title={row.os_image}>
                  {row.os_image}
                </td>
                <td class="text-xs tabular-nums font-medium">{row.vmi_count}</td>
                <td class="text-xs tabular-nums">{row.cpu_pct}</td>
                <td class="text-xs tabular-nums">{row.mem_pct}</td>
              </tr>
            <% end %>
          </.pp_table_body>
        </.pp_table>
      </.pp_table_container>
    </div>
    """
  end

  defp node_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], row.name) and
      matches_field?(filters["ready"], if(row.is_ready, do: "Yes", else: "No")) and
      matches_field?(filters["role"], row.role) and
      matches_field?(filters["os"], row.os_image)
  end

  defp dashboard_tab_defs do
    [
      %{id: :dashboard, label: "Dashboard"},
      %{id: :vms, label: "VMs"},
      %{id: :networks, label: "Networks"},
      %{id: :disks, label: "Disks"},
      %{id: :storage_classes, label: "Storage classes"},
      %{id: :nodes, label: "Nodes"},
      %{id: :vm_topology, label: "Topology"}
    ]
  end

  defp load_kubevirt(token) do
    with {:ok, entry} <- KubeconfigStore.get(token),
         {:ok, conn} <- K8sConn.from_session_entry(entry) do
      {vms, vm_err} = safe_list(&KubeVirt.list_virtual_machines/1, conn)
      {vmis, vmi_err} = safe_list(&KubeVirt.list_virtual_machine_instances/1, conn)
      {nodes, node_err} = safe_list(&ClusterInventory.list_nodes/1, conn)
      {pvcs, pvc_err} = safe_list(&ClusterInventory.list_pvcs/1, conn)
      {storage_classes, sc_err} = safe_list(&ClusterExportLists.list_storage_classes/1, conn)
      {node_metrics, metrics_err} = safe_list(&ClusterMetrics.list_node_metrics/1, conn)

      {virt_launcher_pods, _pods_err} =
        safe_list(&ClusterInventory.list_virt_launcher_pods/1, conn)

      {pod_metrics, _pod_metrics_err} = safe_list(&ClusterMetrics.list_pod_metrics/1, conn)

      {kubernetes_version, kubernetes_version_error} =
        cluster_version_result(&ClusterVersion.kubernetes_git_version/1, conn)

      {kubevirt_version, kubevirt_version_error} =
        cluster_version_result(&ClusterVersion.kubevirt_release_version/1, conn)

      prometheus = prometheus_bootstrap_from_server_or_client()

      {:ok,
       %{
         kubevirt: %{
           cluster: conn.cluster_name,
           user: conn.user_name,
           vms: vms,
           vmis: vmis,
           nodes: nodes,
           pvcs: pvcs,
           storage_classes: storage_classes,
           node_metrics: node_metrics,
           metrics_error: metrics_err,
           virt_launcher_pods: virt_launcher_pods,
           pod_metrics: pod_metrics,
           prometheus: prometheus,
           vm_error: vm_err,
           vmi_error: vmi_err,
           node_error: node_err,
           pvc_error: pvc_err,
           storage_class_error: sc_err,
           kubernetes_version: kubernetes_version,
           kubernetes_version_error: kubernetes_version_error,
           kubevirt_version: kubevirt_version,
           kubevirt_version_error: kubevirt_version_error
         }
       }}
    else
      :error ->
        {:error, :invalid_session}

      {:error, reason} ->
        {:error, K8sSafeError.user_facing(reason)}
    end
  end

  defp safe_list(fun, conn) do
    case fun.(conn) do
      {:ok, items} -> {items, nil}
      {:error, reason} -> {[], reason}
    end
  end

  defp cluster_version_result(fun, conn) when is_function(fun, 1) do
    case fun.(conn) do
      {:ok, v} when is_binary(v) -> {v, nil}
      {:ok, v} -> {to_string(v), nil}
      {:error, reason} -> {"—", reason}
    end
  end

  defp version_card_hint(nil), do: nil

  defp version_card_hint(reason) do
    K8sSafeError.user_facing(reason)
  end

  # OpenShift Virtualization (CNV) reports status.observedKubeVirtVersion as a
  # full image digest rather than a semver string (unlike upstream KubeVirt) —
  # the value itself isn't wrong, just too long to display without wrapping
  # across several lines. Shorten it the way Docker/Git shorten digests/SHAs,
  # keeping the full value available via the card's title tooltip.
  defp shorten_version_display("sha256:" <> hex = full) when byte_size(hex) >= 12 do
    if String.match?(hex, ~r/^[0-9a-f]+$/) do
      "sha256:" <> String.slice(hex, 0, 12) <> "…"
    else
      full
    end
  end

  defp shorten_version_display(other), do: other

  defp prometheus_bootstrap_from_server_or_client do
    case PrometheusMetricsServer.get_latest() do
      {:ok, snap} ->
        Map.put(snap, :ok, true)

      {:error, reason} when is_binary(reason) ->
        %{
          ok: false,
          url: PrometheusSetup.base_url(),
          sum_up: nil,
          prometheus_version: nil,
          node_detail: nil,
          error: reason
        }

      nil ->
        case PrometheusClient.snapshot() do
          {:ok, snap} ->
            Map.put(snap, :ok, true)

          {:error, reason} ->
            %{
              ok: false,
              url: PrometheusSetup.base_url(),
              sum_up: nil,
              prometheus_version: nil,
              node_detail: nil,
              error: reason
            }
        end
    end
  end

  defp metrics(data, prom_live) do
    vms = data.vms || []
    vmis = data.vmis || []
    nodes = data.nodes || []
    pvcs = data.pvcs || []

    {running, stopped, other} = vm_status_counts(vms)
    {vmi_run, vmi_not_run, vmi_other} = vmi_phase_counts(vmis)

    {labels, counts, guest_cpu_totals, mems} = node_resource_rows(nodes, vmis)

    node_resource_chart_height_px =
      DashboardCharts.node_horizontal_chart_height_px(length(labels))

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

    embed =
      Map.get(data, :prometheus) ||
        %{ok: false, error: "unavailable", url: PrometheusSetup.base_url()}

    prom = resolve_prometheus_embed(embed, prom_live)

    prom_ok? = prom[:ok] == true
    prom_url = prom[:url] || PrometheusSetup.base_url()

    usage = ClusterMetrics.usage_summary(nodes, node_metrics, pvcs)

    prom_detail =
      prom[:node_detail] ||
        %{cpu_cluster_pct: nil, mem_cluster_pct: nil, load_buckets: [0, 0, 0, 0]}

    usage_cpu_eff = override_usage_from_prometheus(usage.cpu, prom_detail[:cpu_cluster_pct])
    usage_mem_eff = override_usage_from_prometheus(usage.memory, prom_detail[:mem_cluster_pct])

    usage_cpu_overlay =
      case usage_cpu_eff do
        {:ok, _, _} -> nil
        {:unavailable, _, _} -> cluster_usage_prometheus_hint_text()
      end

    usage_mem_overlay =
      case usage_mem_eff do
        {:ok, _, _} -> nil
        {:unavailable, _, _} -> cluster_usage_prometheus_hint_text()
      end

    {u_cpu_val, u_cpu_sub, u_cpu_hi} = usage_card_fields(usage_cpu_eff)
    {u_mem_val, u_mem_sub, u_mem_hi} = usage_card_fields(usage_mem_eff)

    load_buckets = prom_detail[:load_buckets] || [0, 0, 0, 0]
    node_load_from_prometheus? = Enum.sum(load_buckets) > 0

    node_load_chart_height_px =
      max(220, DashboardCharts.node_horizontal_chart_height_px(4))

    %{
      total_vms: length(vms),
      running: running,
      stopped: stopped,
      other_vm: other,
      total_guest_cpu_cores: Enum.sum(Map.values(guest_cpu_cores_by_vmi_name(vmis))),
      nodes_ready: nodes_ready,
      nodes_schedulable: nodes_schedulable,
      nodes_cordoned: nodes_cordoned,
      nodes_not_ready: nodes_not_ready,
      nodes_total: nodes_total,
      pvc_total: length(pvcs),
      node_labels: labels,
      node_vm_counts: counts,
      node_guest_cpu_totals: guest_cpu_totals,
      node_mem_mib: mems,
      node_resource_chart_height_px: node_resource_chart_height_px,
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
      usage_cpu_overlay: usage_cpu_overlay,
      usage_mem_overlay: usage_mem_overlay,
      prometheus_ok?: prom_ok?,
      prometheus_url: prom_url,
      node_load_from_prometheus?: node_load_from_prometheus?,
      node_load_buckets: load_buckets,
      node_load_chart_height_px: node_load_chart_height_px,
      prometheus_node_detail: prom[:node_detail] || %{}
    }
  end

  defp resolve_prometheus_embed(embed, prom_live) do
    case prom_live do
      nil ->
        embed

      {:ok, live} ->
        Map.put(live, :ok, true)

      {:error, reason} when is_binary(reason) ->
        %{
          ok: false,
          error: reason,
          url: Map.get(embed, :url) || PrometheusSetup.base_url(),
          sum_up: nil,
          prometheus_version: nil,
          node_detail: %{cpu_cluster_pct: nil, mem_cluster_pct: nil, load_buckets: [0, 0, 0, 0]}
        }
    end
  end

  defp override_usage_from_prometheus({:ok, _, _} = ok, _), do: ok

  defp override_usage_from_prometheus({:unavailable, _, _}, pct) when is_float(pct) do
    p = pct |> round() |> min(100) |> max(0)
    {:ok, "#{p}%", "from Prometheus (cluster avg.)"}
  end

  defp override_usage_from_prometheus(other, _), do: other

  defp usage_card_fields({:ok, value, sub}),
    do: {value, sub, ClusterMetrics.highlight_for_usage({:ok, value, sub})}

  defp usage_card_fields({:unavailable, value, sub}), do: {value, sub, :neutral}
end
