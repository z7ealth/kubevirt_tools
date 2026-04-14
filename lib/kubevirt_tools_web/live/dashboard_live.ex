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
  alias KubevirtTools.VmExport
  alias KubevirtTools.VmTopology
  alias KubevirtTools.PrometheusClient
  alias KubevirtTools.PrometheusMetricsServer
  alias KubevirtTools.PrometheusSetup

  @cluster_usage_prometheus_hint "Prometheus not detected, either install it or set PROMETHEUS_URL to where its running"

  @impl true
  def mount(_params, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Dashboard")
      |> assign(:current_scope, %{})
      |> assign(:active_tab, :dashboard)
      |> assign(:prometheus_live, nil)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(KubevirtTools.PubSub, PrometheusMetricsServer.topic())

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
    tab_atom =
      case tab do
        "dashboard" -> :dashboard
        "vms" -> :vms
        "networks" -> :networks
        "disks" -> :disks
        "storage_classes" -> :storage_classes
        "nodes" -> :nodes
        "vm_topology" -> :vm_topology
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
                <div class="flex items-center gap-3 rounded-xl border border-base-300/70 bg-base-200/40 px-5 py-12 text-base-content/70">
                  <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
                  <span>Loading cluster snapshot…</span>
                </div>
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
                <div class="alert alert-error">
                  <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
                  <span>Could not load cluster data. Try refreshing or signing in again.</span>
                </div>
              </div>
            </:failed>

            <% m = metrics(data, @prometheus_live) %>
            <% snap = to_string(data.snapshot_at) %>
            <div class="flex flex-col gap-4 pb-3 lg:flex-row lg:items-center lg:justify-between">
              <div class="min-w-0">
                <p class="text-xs font-medium uppercase tracking-wider text-primary/90">Overview</p>
                <h1 class="text-2xl font-semibold tracking-tight mt-1">KubeVirt Tools</h1>
                <p class="text-sm text-base-content/60 mt-1">
                  Cluster-wide Virtualization Insights
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-xs text-base-content/50 hidden sm:inline">Export</span>
                <.link
                  href={~p"/export/vms.xlsx"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-ghost btn-xs gap-1"
                  id="dashboard-export-xlsx"
                  title="Download cluster inventory as Excel (VirtualMachines sheet matches CSV)"
                >
                  XLSX
                </.link>
                <.link
                  href={~p"/export/vms.csv"}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="btn btn-ghost btn-xs gap-1"
                  id="dashboard-export-csv"
                  title="Download VirtualMachines as CSV"
                >
                  CSV
                </.link>
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
                      <.icon name="hero-chart-bar-square" class="size-5 text-primary" />
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
                    <span class="shrink-0 font-semibold uppercase tracking-wide text-base-content/55">
                      Current context
                    </span>
                    <span class="badge badge-ghost badge-sm gap-1 font-mono px-3 py-2 h-auto whitespace-normal text-base-content/80">
                      {data.user} @ {data.cluster}
                    </span>
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
                      value={data.kubevirt_version}
                      hint={version_card_hint(data.kubevirt_version_error)}
                    />
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
                      class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                      id={"chart-vm-per-node-#{snap}"}
                      title="VMIs per node"
                      height={"#{m.node_resource_chart_height_px}px"}
                      opts={DashboardCharts.vms_per_node_bar(m.node_labels, m.node_vm_counts)}
                    />
                    <.apex_chart
                      class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                      id={"chart-guest-cpu-node-#{snap}"}
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
                      id={"chart-mem-node-#{snap}"}
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
                    <%= if m.node_load_from_prometheus? do %>
                      <.apex_chart
                        class="min-w-0 max-h-[min(85vh,720px)] overflow-y-auto"
                        id={"chart-node-load-#{m.prom_chart_rev}"}
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
                      <.node_load_chart_placeholder id={"node-load-chart-placeholder-#{snap}"} />
                    <% end %>
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
                class="space-y-6 scroll-mt-24 pt-1"
              >
                <section id="vms" class="space-y-3">
                  <div>
                    <h2 class="text-lg font-medium flex items-center gap-2">
                      <.icon name="hero-computer-desktop" class="size-5 text-primary" />
                      Virtual machines
                      <.tab_heading_hint
                        id="dashboard-tab-vms-hint"
                        tip="Each row is a VirtualMachine with live instance fields from the matching VMI (same namespace and name) when it exists."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.vmi_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list VMIs — join columns will be empty ({vm_error_text(
                          data.vmi_error
                        )}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <div class="mt-1">
                      <.virtual_machines_table
                        items={data.vms}
                        vmis={if(data.vmi_error, do: [], else: data.vmis)}
                        pvcs={List.wrap(data.pvcs)}
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
                      <.icon name="hero-wifi" class="size-5 text-primary" /> VM network interfaces
                      <.tab_heading_hint
                        id="dashboard-tab-networks-hint"
                        tip="Declared on each VirtualMachine template (spec.template.spec.domain.devices.interfaces), with live MAC, IP, and guest interface name from the matching VMI when running."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_network_interfaces_table
                      vms={data.vms}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
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
                      <.icon name="hero-circle-stack" class="size-5 text-primary" />
                      VM disks &amp; volumes
                      <.tab_heading_hint
                        id="dashboard-tab-disks-hint"
                        tip="Block devices from spec.template.spec.domain.devices.disks linked to template volumes; size and storage class use DataVolume templates and cluster PVCs when resolvable."
                      />
                    </h2>
                  </div>
                  <%= if data.vm_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_disks_detail_table
                      vms={data.vms}
                      pvcs={List.wrap(data.pvcs)}
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
                      <.icon name="hero-archive-box" class="size-5 text-primary" /> Storage classes
                      <.tab_heading_hint
                        id="dashboard-tab-storage-classes-hint"
                        tip="Cluster-scoped StorageClass objects from storage.k8s.io/v1. PVC counts use spec.storageClassName from all namespaces; PVCs with no class set are listed separately. Names on PVCs that do not match any listed class may be typos or removed classes."
                      />
                    </h2>
                  </div>
                  <%= if data.storage_class_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list StorageClasses ({vm_error_text(data.storage_class_error)}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.storage_class_error == nil do %>
                    <.storage_classes_table
                      storage_classes={List.wrap(data.storage_classes)}
                      pvcs={List.wrap(data.pvcs)}
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
                      <.icon name="hero-server-stack" class="size-5 text-primary" /> Nodes
                      <.tab_heading_hint
                        id="dashboard-tab-nodes-hint"
                        tip="Kubernetes Nodes from the cluster API (status.addresses, allocatable resources, conditions). CPU and memory % prefer metrics-server NodeMetrics; when that API is missing, values are taken from Prometheus node_exporter (same queries as the dashboard) when scrape targets match the node name, hostname, or internal IP. VMIs counts use VMI status.nodeName."
                      />
                    </h2>
                  </div>
                  <%= if data.node_error do %>
                    <div class="alert alert-warning text-sm">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        Could not list Nodes ({vm_error_text(data.node_error)}).
                      </span>
                    </div>
                  <% end %>
                  <%= if data.metrics_error && not m.prometheus_ok? do %>
                    <div class="alert alert-warning text-sm py-2">
                      <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                      <span>
                        metrics-server NodeMetrics is unavailable ({vm_error_text(data.metrics_error)}). {cluster_usage_prometheus_hint_text()}
                      </span>
                    </div>
                  <% end %>
                  <%= if data.node_error == nil do %>
                    <.nodes_table
                      nodes={List.wrap(data.nodes)}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
                      node_metrics={List.wrap(data.node_metrics)}
                      prometheus_node_detail={m.prometheus_node_detail}
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
                    <.icon name="hero-squares-2x2" class="size-5 text-primary" /> Topology
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

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil

  attr :highlight, :atom,
    values: [:neutral, :primary, :success, :danger, :warning],
    default: :neutral

  defp stat_tile(assigns) do
    value_class =
      case assigns.highlight do
        :primary -> "text-primary"
        :success -> "text-emerald-400"
        :danger -> "text-stopped"
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
        :primary -> "text-primary"
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
      <div
        id={@id}
        class="rounded-xl border border-base-300/60 bg-base-200/40 px-4 py-3 transition hover:border-primary/30 hover:bg-base-200/70"
      >
        <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50">
          {@label}
        </p>
        <p class={["text-xl font-semibold tabular-nums mt-1", @value_class]}>{@value}</p>
        <p :if={@sub} class="text-xs text-base-content/45 mt-0.5">{@sub}</p>
      </div>
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :hint, :string, default: nil

  defp dashboard_version_card(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "rounded-xl border border-base-300/60 bg-base-200/40 px-4 py-3 min-w-0 w-full",
        "transition hover:border-primary/30 hover:bg-base-200/70"
      ]}
    >
      <p class="text-[0.65rem] font-semibold uppercase tracking-wide text-base-content/50">
        {@label}
      </p>
      <p class="text-xl font-semibold tabular-nums mt-1 text-base-content break-words leading-snug">
        {@value}
      </p>
      <p :if={@hint} class="text-xs text-base-content/55 mt-1.5 leading-snug">{@hint}</p>
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
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp virtual_machines_table(assigns) do
    assigns =
      assigns
      |> assign(:vmi_lookup, vmi_index_by_ns_name(List.wrap(assigns.vmis)))
      |> assign(:pvc_by_ns_claim, pvc_requests_by_namespace_claim(List.wrap(assigns.pvcs)))

    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>VM phase</th>
            <th title="template.spec.domain.firmware.bootloader">Boot mode</th>
            <th>Cores</th>
            <th>Sockets</th>
            <th>CPUs (guest)</th>
            <th>Memory</th>
            <th>VMI phase</th>
            <th>Node</th>
            <th>IP</th>
            <th>Disks</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@items == []}>
            <td colspan="13" class="text-center text-base-content/50 py-8">{@empty_label}</td>
          </tr>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <% vmi = vmi_lookup_match(@vmi_lookup, item) %>
            <% {cores, sockets, guest_cpu_total} = virtual_machine_cpu_topology_cells(item, vmi) %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs whitespace-nowrap">{vm_meta(item, :namespace)}</td>
              <td class="font-medium whitespace-nowrap">{vm_meta(item, :name)}</td>
              <td>
                <span class={vm_phase_badge_classes(item)}>{vm_phase(item)}</span>
              </td>
              <td class="text-xs text-base-content/80 whitespace-nowrap">{vm_boot_mode(item)}</td>
              <td class="text-xs tabular-nums" title="Cores per socket (domain.cpu.cores)">
                {cores}
              </td>
              <td class="text-xs tabular-nums" title="Socket count (domain.cpu.sockets)">
                {sockets}
              </td>
              <td class="text-xs tabular-nums font-medium" title="sockets × cores × threads">
                {guest_cpu_total}
              </td>
              <td class="text-xs font-mono text-base-content/75">{memory_for_vm_row(item, vmi)}</td>
              <td>
                <span :if={vmi} class="badge badge-sm badge-ghost">{vmi_phase(vmi)}</span>
                <span :if={!vmi} class="text-xs text-base-content/45">—</span>
              </td>
              <td
                class="font-mono text-xs text-base-content/70 max-w-[10rem] truncate"
                title={vmi_scheduling_node_name(vmi || %{})}
              >
                {if(vmi, do: vmi_scheduling_node_name(vmi), else: "—")}
              </td>
              <td
                class="font-mono text-xs text-base-content/80 max-w-[9rem] truncate"
                title={if(vmi, do: vmi_primary_ip(vmi), else: "")}
              >
                {if(vmi, do: vmi_primary_ip(vmi), else: "—")}
              </td>
              <td
                class="text-xs tabular-nums text-base-content/85 whitespace-nowrap"
                title={vm_disk_column_title(item, @pvc_by_ns_claim)}
              >
                {vm_disk_column(item, @pvc_by_ns_claim)}
              </td>
              <td class="text-xs text-base-content/60 whitespace-nowrap">
                {vm_meta(item, :created)}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :id_prefix, :string, required: true

  defp orphan_virtual_machine_instance_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
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
        </thead>
        <tbody>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs whitespace-nowrap">{vm_meta(item, :namespace)}</td>
              <td class="font-medium whitespace-nowrap">{vm_meta(item, :name)}</td>
              <td>
                <span class="badge badge-sm badge-outline">{vmi_phase(item)}</span>
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
        </tbody>
      </table>
    </div>
    """
  end

  attr :vms, :list, required: true
  attr :vmis, :list, default: []
  attr :id_prefix, :string, required: true

  defp virtual_machine_network_interfaces_table(assigns) do
    rows = virtual_machine_network_interface_rows(assigns.vms, List.wrap(assigns.vmis))
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>VM</th>
            <th>Interface</th>
            <th>Model</th>
            <th>Binding</th>
            <th>MAC (spec)</th>
            <th>MAC (VMI)</th>
            <th>IP addresses</th>
            <th>Guest iface</th>
            <th>VMI phase</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="10" class="text-center text-base-content/50 py-8">
              No network interfaces defined on any VirtualMachine.
            </td>
          </tr>
          <%= for {row, i} <- Enum.with_index(@rows) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs whitespace-nowrap">{row.namespace}</td>
              <td class="font-medium whitespace-nowrap">{row.vm_name}</td>
              <td class="text-xs font-mono text-base-content/80">{row.iface_name}</td>
              <td class="text-xs">{row.model}</td>
              <td class="text-xs whitespace-nowrap">{row.binding}</td>
              <td class="font-mono text-xs text-base-content/70">{row.mac_spec}</td>
              <td class="font-mono text-xs text-base-content/70">{row.mac_live}</td>
              <td
                class="font-mono text-xs text-base-content/80 max-w-[14rem] truncate"
                title={row.ips}
              >
                {row.ips}
              </td>
              <td class="font-mono text-xs text-base-content/70">{row.guest_iface}</td>
              <td>
                <span class="badge badge-sm badge-ghost">{row.vmi_phase}</span>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :vms, :list, required: true
  attr :pvcs, :list, default: []
  attr :id_prefix, :string, required: true

  defp virtual_machine_disks_detail_table(assigns) do
    rows = virtual_machine_disk_detail_rows(assigns.vms, List.wrap(assigns.pvcs))
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>VM</th>
            <th>Disk</th>
            <th>Device</th>
            <th>Bus</th>
            <th>Boot</th>
            <th>Removable</th>
            <th>Volume kind</th>
            <th>Source</th>
            <th>Size</th>
            <th>Storage class</th>
            <th>PVC phase</th>
            <th>Serial</th>
            <th>Cache</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="14" class="text-center text-base-content/50 py-8">
              No disks defined on any VirtualMachine.
            </td>
          </tr>
          <%= for {row, i} <- Enum.with_index(@rows) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs whitespace-nowrap">{row.namespace}</td>
              <td class="font-medium whitespace-nowrap">{row.vm_name}</td>
              <td class="text-xs font-mono text-base-content/80">{row.disk_name}</td>
              <td class="text-xs">{row.device_kind}</td>
              <td class="text-xs font-mono">{row.bus}</td>
              <td class="text-xs tabular-nums">{row.boot_order}</td>
              <td>
                <%= if row.removable? do %>
                  <span class="badge badge-xs badge-warning">Yes</span>
                <% else %>
                  <span class="text-xs text-base-content/45">No</span>
                <% end %>
              </td>
              <td class="text-xs whitespace-nowrap">{row.volume_kind}</td>
              <td
                class="text-xs font-mono text-base-content/75 max-w-[12rem] truncate"
                title={row.source}
              >
                {row.source}
              </td>
              <td class="text-xs tabular-nums whitespace-nowrap">{row.size}</td>
              <td class="text-xs max-w-[8rem] truncate" title={row.storage_class}>
                {row.storage_class}
              </td>
              <td class="text-xs">{row.pvc_phase}</td>
              <td class="font-mono text-xs text-base-content/65">{row.serial}</td>
              <td class="text-xs font-mono text-base-content/65">{row.cache}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :storage_classes, :list, required: true
  attr :pvcs, :list, required: true
  attr :id_prefix, :string, required: true

  defp storage_classes_table(assigns) do
    pvc_by_class = pvc_counts_by_storage_class_name(assigns.pvcs)
    sc_names = storage_class_name_set(assigns.storage_classes)
    rows = storage_classes_table_rows(assigns.storage_classes, pvc_by_class)
    orphan_refs = orphan_storage_class_refs_with_counts(pvc_by_class, sc_names)
    unset_count = Map.get(pvc_by_class, "", 0)

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:orphan_refs, orphan_refs)
      |> assign(:unset_count, unset_count)

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
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Name</th>
            <th>Default</th>
            <th>Provisioner</th>
            <th>Reclaim</th>
            <th>Binding</th>
            <th title="spec.allowVolumeExpansion">Expand</th>
            <th title="PVCs in the cluster using this storageClassName">PVCs</th>
            <th>Parameters</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="8" class="text-center text-base-content/50 py-8">
              No StorageClass objects returned from the API.
            </td>
          </tr>
          <%= for {row, i} <- Enum.with_index(@rows) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs font-medium whitespace-nowrap">{row.name}</td>
              <td>
                <%= if row.default? do %>
                  <span class="badge badge-xs badge-primary">default</span>
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
              <td class="text-xs whitespace-nowrap">{row.reclaim}</td>
              <td class="text-xs whitespace-nowrap">{row.binding}</td>
              <td class="text-xs">
                <%= cond do %>
                  <% row.expand == true -> %>
                    <span class="badge badge-xs badge-success">Yes</span>
                  <% row.expand == false -> %>
                    <span class="text-base-content/50">No</span>
                  <% true -> %>
                    <span class="text-base-content/40">—</span>
                <% end %>
              </td>
              <td class="text-xs tabular-nums font-medium">{row.pvc_count}</td>
              <td
                class="text-xs font-mono text-base-content/70 max-w-[18rem] truncate"
                title={row.parameters_full}
              >
                {row.parameters_display}
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
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

  attr :nodes, :list, required: true
  attr :vmis, :list, default: []
  attr :node_metrics, :list, default: []
  attr :prometheus_node_detail, :map, default: %{}
  attr :id_prefix, :string, required: true

  defp nodes_table(assigns) do
    merged =
      nodes_merged_usage_map(
        assigns.nodes,
        assigns.node_metrics,
        assigns.prometheus_node_detail || %{}
      )

    rows = kubernetes_nodes_table_rows(assigns.nodes, assigns.vmis, merged)
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Name</th>
            <th>Ready</th>
            <th>Scheduling</th>
            <th>Role</th>
            <th>VMIs</th>
            <th title="metrics-server (usage / allocatable) when available; else Prometheus node_exporter per target">
              CPU %
            </th>
            <th title="metrics-server (usage / allocatable) when available; else Prometheus node_exporter per target">
              Mem %
            </th>
            <th>Internal IP</th>
            <th>External IP</th>
            <th title="status.allocatable.cpu">CPU (alloc.)</th>
            <th title="status.allocatable.memory">Memory (alloc.)</th>
            <th title="status.allocatable.pods">Max pods</th>
            <th>Kubelet</th>
            <th>OS / arch</th>
            <th title="status.nodeInfo.containerRuntimeVersion">Runtime</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@rows == []}>
            <td colspan="15" class="text-center text-base-content/50 py-8">
              No nodes returned from the API.
            </td>
          </tr>
          <%= for {row, i} <- Enum.with_index(@rows) do %>
            <tr
              id={"#{@id_prefix}-row-#{i}"}
              class="hover:bg-base-200/40 transition-colors"
              title={row.scheduling_hint}
            >
              <td class="font-mono text-xs font-medium whitespace-nowrap">{row.name}</td>
              <td>
                <%= if row.is_ready do %>
                  <span class="badge badge-sm badge-success">Yes</span>
                <% else %>
                  <span class="badge badge-sm badge-error">No</span>
                <% end %>
              </td>
              <td class="text-xs whitespace-nowrap">{row.scheduling}</td>
              <td>
                <span class="badge badge-sm badge-ghost font-mono text-[0.7rem]">{row.role}</span>
              </td>
              <td class="text-xs tabular-nums font-medium">{row.vmi_count}</td>
              <td class="text-xs tabular-nums">{row.cpu_pct}</td>
              <td class="text-xs tabular-nums">{row.mem_pct}</td>
              <td
                class="font-mono text-xs text-base-content/80 max-w-[9rem] truncate"
                title={row.internal_ip}
              >
                {row.internal_ip}
              </td>
              <td
                class="font-mono text-xs text-base-content/70 max-w-[9rem] truncate"
                title={row.external_ip}
              >
                {row.external_ip}
              </td>
              <td class="text-xs font-mono tabular-nums">{row.cpu_alloc}</td>
              <td class="text-xs font-mono tabular-nums">{row.mem_alloc}</td>
              <td class="text-xs tabular-nums">{row.pods_alloc}</td>
              <td
                class="text-xs font-mono text-base-content/75 max-w-[8rem] truncate"
                title={row.kubelet}
              >
                {row.kubelet}
              </td>
              <td class="text-xs max-w-[10rem] truncate" title={row.os_arch}>{row.os_arch}</td>
              <td
                class="text-xs font-mono text-base-content/65 max-w-[12rem] truncate"
                title={row.runtime}
              >
                {row.runtime}
              </td>
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
           prometheus: prometheus,
           vm_error: vm_err,
           vmi_error: vmi_err,
           node_error: node_err,
           pvc_error: pvc_err,
           storage_class_error: sc_err,
           kubernetes_version: kubernetes_version,
           kubernetes_version_error: kubernetes_version_error,
           kubevirt_version: kubevirt_version,
           kubevirt_version_error: kubevirt_version_error,
           snapshot_at: System.system_time(:millisecond)
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

    prom_chart_rev =
      case prom_live do
        {:ok, %{fetched_at: t}} -> t
        _ -> Map.get(data, :snapshot_at, 0)
      end

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
      prom_chart_rev: prom_chart_rev,
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

  defp guest_cpu_cores_by_vmi_name(vmis) do
    for vmi <- vmis, into: %{} do
      name = vm_meta(vmi, :name)
      cores = vmi_guest_cpu_core_count(vmi)
      {name, cores}
    end
  end

  defp vmi_guest_cpu_core_count(vmi) do
    case get_in(vmi, ["spec", "domain", "cpu", "cores"]) do
      n when is_integer(n) and n > 0 -> n
      _ -> 1
    end
  end

  defp node_resource_rows(nodes, vmis) do
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

  defp fallback_node_rows_from_grouped(grouped) do
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

  defp pvc_counts_by_storage_class_name(pvcs) when is_list(pvcs) do
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

  defp storage_class_name_set(storage_classes) when is_list(storage_classes) do
    MapSet.new(
      for sc <- storage_classes,
          n = get_in(sc, ["metadata", "name"]),
          is_binary(n),
          do: n
    )
  end

  defp orphan_storage_class_refs_with_counts(pvc_by_class, sc_names) do
    pvc_by_class
    |> Enum.reject(fn {k, _} -> k == "" end)
    |> Enum.reject(fn {k, _} -> MapSet.member?(sc_names, k) end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp orphan_storage_class_refs_pretty([]), do: ""

  defp orphan_storage_class_refs_pretty(refs) do
    refs
    |> Enum.map(fn {name, n} ->
      if n == 1, do: "#{name} (1 PVC)", else: "#{name} (#{n} PVCs)"
    end)
    |> Enum.join(", ")
  end

  defp storage_classes_table_rows(storage_classes, pvc_by_class) when is_list(storage_classes) do
    storage_classes
    |> Enum.sort_by(&get_in(&1, ["metadata", "name"]))
    |> Enum.map(&storage_class_table_row(&1, pvc_by_class))
  end

  defp storage_class_table_row(sc, pvc_by_class) do
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

  defp storage_class_default_annotation?(sc) do
    case get_in(sc, ["metadata", "annotations", "storageclass.kubernetes.io/is-default-class"]) do
      "true" -> true
      true -> true
      _ -> false
    end
  end

  defp format_sc_reclaim(nil), do: "Delete"
  defp format_sc_reclaim(""), do: "Delete"
  defp format_sc_reclaim(s), do: to_string(s)

  defp format_sc_binding(nil), do: "Immediate"
  defp format_sc_binding(""), do: "Immediate"
  defp format_sc_binding(s), do: to_string(s)

  defp storage_class_parameters_display(nil), do: {"—", ""}

  defp storage_class_parameters_display(params) when params == %{}, do: {"—", ""}

  defp storage_class_parameters_display(params) when is_map(params) do
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

  defp storage_class_parameters_display(_), do: {"—", ""}

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

  defp vm_error_text(err), do: K8sSafeError.user_facing(err)

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

  defp vm_phase_badge_classes(vm) do
    phase =
      vm
      |> vm_phase()
      |> to_string()
      |> String.trim()
      |> String.downcase()

    extra =
      cond do
        phase in ["", "—"] ->
          ["badge-ghost", "border", "border-base-300/55", "text-base-content/75"]

        phase == "running" ->
          ["badge-success"]

        phase == "stopped" ->
          ["badge-neutral"]

        phase in [
          "starting",
          "stopping",
          "terminating",
          "migrating",
          "provisioning",
          "paused"
        ] ->
          ["badge-warning"]

        String.contains?(phase, "error") or String.contains?(phase, "failed") or
            String.contains?(phase, "crash") ->
          [
            "border-0",
            "bg-[color:var(--color-stopped)]",
            "text-[color:var(--color-stopped-content)]",
            "shadow-sm"
          ]

        String.contains?(phase, "waiting") or String.contains?(phase, "pending") or
            phase == "unknown" ->
          ["badge-info"]

        true ->
          ["badge-ghost", "border", "border-base-300/55", "text-base-content/80"]
      end

    ["badge", "badge-sm"] ++ extra
  end

  defp vmi_phase(item) do
    get_in(item, ["status", "phase"]) || "—"
  end

  defp vmi_scheduling_node_name(item) do
    get_in(item, ["status", "nodeName"]) || "—"
  end

  defp vmi_index_by_ns_name(vmis) when is_list(vmis) do
    for vmi <- vmis, into: %{} do
      k = {vm_meta(vmi, :namespace), vm_meta(vmi, :name)}
      {k, vmi}
    end
  end

  defp vmi_lookup_match(lookup, vm) when is_map(lookup) and is_map(vm) do
    Map.get(lookup, {vm_meta(vm, :namespace), vm_meta(vm, :name)})
  end

  defp vmi_orphans_without_vm(vms, vmis) when is_list(vms) and is_list(vmis) do
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

  defp virtual_machine_cpu_topology_cells(vm, vmi) do
    vm
    |> virtual_machine_cpu_domain_for_row(vmi)
    |> format_domain_cpu_topology()
  end

  defp virtual_machine_cpu_domain_for_row(vm, vmi) do
    vmi_cpu = vmi && get_in(vmi, ["spec", "domain", "cpu"])
    vm_cpu = get_in(vm, ["spec", "template", "spec", "domain", "cpu"])

    if domain_cpu_has_numeric_topology?(vmi_cpu) do
      vmi_cpu
    else
      vm_cpu
    end
  end

  defp domain_cpu_has_numeric_topology?(nil), do: false

  defp domain_cpu_has_numeric_topology?(cpu) when is_map(cpu) do
    Enum.any?(["cores", "sockets", "threads"], fn k ->
      case cpu[k] do
        nil -> false
        n when is_integer(n) and n >= 1 -> true
        n when is_binary(n) -> match?({i, _} when i >= 1, Integer.parse(String.trim(n)))
        _ -> false
      end
    end)
  end

  defp format_domain_cpu_topology(nil), do: {"1", "1", "1"}

  defp format_domain_cpu_topology(cpu) when is_map(cpu) do
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

  defp cpu_topology_int(nil), do: nil

  defp cpu_topology_int(n) when is_integer(n) and n >= 1, do: n

  defp cpu_topology_int(n) when is_binary(n) do
    case Integer.parse(String.trim(n)) do
      {i, _} when i >= 1 -> i
      _ -> nil
    end
  end

  defp cpu_topology_int(_), do: nil

  defp memory_for_vm_row(vm, nil), do: vm_spec_memory_guest(vm)

  defp memory_for_vm_row(vm, vmi) do
    case get_in(vmi, ["spec", "domain", "memory", "guest"]) do
      nil -> vm_spec_memory_guest(vm)
      s -> format_cell(s)
    end
  end

  defp vm_boot_mode(vm), do: VmExport.boot_mode_label(vm)

  defp vm_spec_memory_guest(vm) do
    format_cell(get_in(vm, ["spec", "template", "spec", "domain", "memory", "guest"]))
  end

  defp vmi_spec_cpu_cores(item) do
    case cpu_topology_int(get_in(item, ["spec", "domain", "cpu", "cores"])) do
      nil -> "1"
      n -> Integer.to_string(n)
    end
  end

  defp vmi_spec_memory_guest(item) do
    format_cell(get_in(item, ["spec", "domain", "memory", "guest"]))
  end

  defp vmi_primary_ip(item) do
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

  defp vmi_ready_label(item) do
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

  # CD-ROM / floppy are treated as removable; everything else (disk, lun, …) counts.
  defp vm_disk_device_removable?(%{} = d) do
    Map.has_key?(d, "cdrom") or Map.has_key?(d, "floppy")
  end

  defp vm_non_removable_disks(vm) do
    disks = get_in(vm, ["spec", "template", "spec", "domain", "devices", "disks"]) || []
    Enum.reject(disks, &vm_disk_device_removable?/1)
  end

  defp vm_template_volume_by_name(vm) do
    vols = get_in(vm, ["spec", "template", "spec", "volumes"]) || []

    Map.new(vols, fn v ->
      {v["name"], v}
    end)
  end

  defp vm_data_volume_template_by_name(vm) do
    tpls = get_in(vm, ["spec", "dataVolumeTemplates"]) || []

    Map.new(tpls, fn t ->
      {get_in(t, ["metadata", "name"]), t}
    end)
  end

  defp vm_volume_storage_gib_contribution(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
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

  defp pvc_claim_namespace(vol, vm_ns) do
    case get_in(vol, ["persistentVolumeClaim", "namespace"]) do
      ns when is_binary(ns) and ns != "" -> ns
      _ -> if(vm_ns in [nil, "", "—"], do: nil, else: vm_ns)
    end
  end

  defp pvc_requests_by_namespace_claim(pvcs) when is_list(pvcs) do
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

  defp vm_non_removable_disk_storage_sum_gib(vm, pvc_by_ns_claim) do
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

  defp vm_disk_column(vm, pvc_by_ns_claim) do
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

  defp vm_disk_column_title(vm, pvc_by_ns_claim) do
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
  defp gib_sum_to_decimal_gb(gib) when is_float(gib) and gib >= 0 do
    gib * 1_073_741_824 / 1_000_000_000
  end

  defp format_decimal_gb_display(gb) when is_float(gb) do
    rounded = Float.round(gb, 2)

    if rounded == trunc(rounded) * 1.0 do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, decimals: 2)
    end
  end

  defp parse_k8s_quantity_to_gib(q) when q in [nil, ""], do: 0.0

  defp parse_k8s_quantity_to_gib(q) when is_binary(q) do
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

  defp parse_k8s_quantity_to_gib(q), do: parse_k8s_quantity_to_gib(to_string(q))

  defp k8s_storage_suffix_to_gib_multiplier(""), do: 0.0
  defp k8s_storage_suffix_to_gib_multiplier("gi"), do: 1.0
  defp k8s_storage_suffix_to_gib_multiplier("g"), do: 1.0
  defp k8s_storage_suffix_to_gib_multiplier("mi"), do: 1.0 / 1024
  defp k8s_storage_suffix_to_gib_multiplier("m"), do: 1.0 / 1024
  defp k8s_storage_suffix_to_gib_multiplier("ki"), do: 1.0 / 1024 / 1024
  defp k8s_storage_suffix_to_gib_multiplier("k"), do: 1.0 / 1024 / 1024
  defp k8s_storage_suffix_to_gib_multiplier("ti"), do: 1024.0
  defp k8s_storage_suffix_to_gib_multiplier("t"), do: 1024.0
  defp k8s_storage_suffix_to_gib_multiplier(_), do: 0.0

  defp virtual_machine_network_interface_rows(vms, vmis) when is_list(vms) do
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

  defp vmi_status_interfaces_by_name(nil), do: %{}

  defp vmi_status_interfaces_by_name(vmi) do
    ifaces = get_in(vmi, ["status", "interfaces"]) || []
    Map.new(ifaces, fn i -> {i["name"], i} end)
  end

  defp interface_binding_label(iface) when is_map(iface) do
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

  defp format_iface_ips_display(iface) when is_map(iface) do
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

  defp format_iface_ips_display(_), do: "—"

  defp virtual_machine_disk_detail_rows(vms, pvcs) when is_list(vms) do
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
          storage_class: sc,
          pvc_phase: ph,
          serial: disk_device_serial(d),
          cache: disk_device_cache(d)
        }
      end)
    end)
  end

  defp pvc_extended_info_by_ns_claim(pvcs) when is_list(pvcs) do
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

  defp disk_volume_gib(nil, _, _, _), do: 0.0

  defp disk_volume_gib(vol, dvt_by_name, vm_ns, pvc_by_ns_claim) when is_map(vol) do
    vm_volume_storage_gib_contribution(vol, dvt_by_name, vm_ns, pvc_by_ns_claim)
  end

  defp pvc_meta_for_disk_volume(nil, _, _), do: {"—", "—"}

  defp pvc_meta_for_disk_volume(vol, vm_ns, pvc_info) when is_map(vol) do
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

  defp volume_kind_and_ref(nil), do: {"—", "—"}

  defp volume_kind_and_ref(vol) when is_map(vol) do
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

  defp disk_device_kind(%{} = d) do
    cond do
      Map.has_key?(d, "disk") -> "disk"
      Map.has_key?(d, "cdrom") -> "cdrom"
      Map.has_key?(d, "lun") -> "lun"
      Map.has_key?(d, "floppy") -> "floppy"
      true -> "—"
    end
  end

  defp disk_device_bus(%{} = d) do
    sub = d["disk"] || d["cdrom"] || d["lun"] || d["floppy"] || %{}
    format_cell(sub["bus"])
  end

  defp disk_device_serial(%{} = d) do
    sub = d["disk"] || d["cdrom"] || %{}
    format_cell(sub["serial"])
  end

  defp disk_device_cache(%{} = d) do
    sub = d["disk"] || d["cdrom"] || %{}
    format_cell(sub["cache"])
  end

  defp format_disk_size_display(gib) when is_float(gib) and gib > 0 do
    format_decimal_gb_display(gib_sum_to_decimal_gb(gib)) <> " GB"
  end

  defp format_disk_size_display(_), do: "—"

  defp nodes_merged_usage_map(nodes, node_metrics, prometheus_node_detail) do
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

  defp merge_node_usage(ms_row, prom_row) do
    ms_row = ms_row || %{cpu: "—", mem: "—"}
    prom_row = prom_row || %{cpu: "—", mem: "—"}

    %{
      cpu: coalesce_node_usage_pct(ms_row[:cpu], prom_row[:cpu]),
      mem: coalesce_node_usage_pct(ms_row[:mem], prom_row[:mem])
    }
  end

  defp coalesce_node_usage_pct("—", b), do: normalize_usage_pct_display(b)
  defp coalesce_node_usage_pct(nil, b), do: normalize_usage_pct_display(b)
  defp coalesce_node_usage_pct("", b), do: normalize_usage_pct_display(b)
  defp coalesce_node_usage_pct(a, _), do: a

  defp normalize_usage_pct_display(nil), do: "—"
  defp normalize_usage_pct_display("—"), do: "—"
  defp normalize_usage_pct_display(s) when is_binary(s), do: s

  defp prometheus_exporter_pct_by_node(_nodes, detail)
       when detail == nil or detail == %{} do
    %{}
  end

  defp prometheus_exporter_pct_by_node(nodes, detail) when is_map(detail) do
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

  defp prometheus_instance_series(detail, key) do
    List.wrap(Map.get(detail, key) || Map.get(detail, Atom.to_string(key)))
  end

  defp prometheus_label_to_pct_map(entries) do
    Enum.reduce(entries, %{}, fn e, acc ->
      {l, v} = prometheus_entry_label_value(e)

      if is_binary(l) and l != "" and is_float(v) do
        Map.put(acc, l, format_exporter_pct_display(v))
      else
        acc
      end
    end)
  end

  defp prometheus_entry_label_value(e) when is_map(e) do
    l = e[:label] || e["label"]
    v = e[:value] || e["value"]
    v = if is_float(v), do: v, else: if(is_number(v), do: v * 1.0, else: nil)
    {l, v}
  end

  defp format_exporter_pct_display(f) when is_float(f) do
    "#{min(100, max(0, round(f)))}%"
  end

  defp first_exporter_label_match(by_label, candidates) do
    Enum.find_value(candidates, fn c -> Map.get(by_label, c) end) || "—"
  end

  defp node_prometheus_match_labels(node) do
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

  defp kubernetes_nodes_table_rows(nodes, vmis, merged_usage) do
    n_list = nodes |> List.wrap() |> Enum.sort_by(&kubernetes_node_sort_key/1, :asc)
    vmi_counts = vmi_count_by_k8s_node(vmis)
    Enum.map(n_list, &kubernetes_node_table_row(&1, vmi_counts, merged_usage))
  end

  defp kubernetes_node_sort_key(n), do: get_in(n, ["metadata", "name"]) || ""

  defp vmi_count_by_k8s_node(vmis) do
    Enum.reduce(List.wrap(vmis), %{}, fn vmi, acc ->
      case get_in(vmi, ["status", "nodeName"]) do
        n when is_binary(n) and n != "" -> Map.update(acc, n, 1, &(&1 + 1))
        _ -> acc
      end
    end)
  end

  defp kubernetes_node_table_row(node, vmi_counts, usage_map) do
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
      runtime: runtime
    }
  end

  defp kubernetes_node_scheduling_label(node) do
    cond do
      not node_ready?(node) -> "Not ready"
      node_cordoned?(node) -> "Cordoned"
      true -> "Schedulable"
    end
  end

  defp kubernetes_node_not_ready_hint(node) do
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

  defp kubernetes_node_role_label(node) do
    labels = get_in(node, ["metadata", "labels"]) || %{}

    cond do
      Map.has_key?(labels, "node-role.kubernetes.io/control-plane") -> "control-plane"
      Map.has_key?(labels, "node-role.kubernetes.io/master") -> "control-plane"
      true -> "worker"
    end
  end

  defp node_address(node, type) when is_binary(type) do
    addrs = get_in(node, ["status", "addresses"]) || []

    case Enum.find(addrs, &(&1["type"] == type)) do
      %{"address" => a} when is_binary(a) and a != "" -> a
      _ -> "—"
    end
  end

  defp format_cell(nil), do: "—"
  defp format_cell(""), do: "—"
  defp format_cell(val) when is_boolean(val), do: if(val, do: "true", else: "false")
  defp format_cell(val), do: to_string(val)
end
