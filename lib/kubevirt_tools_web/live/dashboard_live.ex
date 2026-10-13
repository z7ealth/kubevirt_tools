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
  alias KubevirtToolsWeb.PaginationComponents

  import VmPresentation

  @cluster_usage_prometheus_hint "Prometheus not detected, either install it or set PROMETHEUS_URL to where its running"

  defp auto_refresh_ms, do: KubevirtTools.EnvConfig.int("POLL_INTERVAL_MS", 60_000)

  # Per-tab column filters. Empty string means "All" (no filter applied).
  @default_filters %{
    "vms" => %{"search" => "", "phase" => "", "node" => "", "agent" => "", "os" => ""},
    "networks" => %{"search" => "", "binding" => "", "vmi_phase" => ""},
    "disks" => %{"search" => "", "volume_kind" => "", "storage_class" => "", "pvc_phase" => ""},
    "storage_classes" => %{"search" => "", "provisioner" => ""},
    "nodes" => %{"search" => "", "status" => "", "role" => "", "os" => ""}
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
      |> assign(:pagination, PaginationComponents.new(Map.keys(@default_sort)))

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

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> update(:pagination, &PaginationComponents.reset_page(&1, tab))}
  end

  @impl true
  def handle_event("clear_filters", %{"tab" => tab}, socket) do
    filters = Map.put(socket.assigns.filters, tab, Map.fetch!(@default_filters, tab))

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> update(:pagination, &PaginationComponents.reset_page(&1, tab))}
  end

  @impl true
  def handle_event("sort", %{"tab" => tab, "field" => field}, socket) do
    next =
      case Map.get(socket.assigns.sort, tab) do
        {^field, :asc} -> {field, :desc}
        {^field, :desc} -> nil
        _ -> {field, :asc}
      end

    {:noreply,
     socket
     |> assign(:sort, Map.put(socket.assigns.sort, tab, next))
     |> update(:pagination, &PaginationComponents.reset_page(&1, tab))}
  end

  @impl true
  def handle_event(event, params, socket) when event in ["set_page", "set_per_page"] do
    {:noreply,
     update(socket, :pagination, &PaginationComponents.handle_pagination_event(&1, event, params))}
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
                <.dashboard_heading />
                <.loading_card id="dashboard-loading" label="Loading cluster snapshot…" />
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="space-y-4">
                <.dashboard_heading />
                <.banner kind={:error} id="dashboard-load-error">
                  Could not load cluster data. Try refreshing or signing in again.
                </.banner>
              </div>
            </:failed>

            <% m = metrics(data, @prometheus_live) %>
            <div class="flex flex-col gap-4 pb-3 lg:flex-row lg:items-center lg:justify-between">
              <.dashboard_heading />
              <div class="flex flex-wrap items-center gap-2">
                <.pp_button_group variant="connected" aria-label="Export">
                  <.pp_button
                    variant="tonal"
                    href={~p"/export/vms.xlsx"}
                    target="_blank"
                    rel="noopener noreferrer"
                    id="dashboard-export-xlsx"
                    title="Download cluster inventory as Excel (VirtualMachines sheet matches CSV)"
                  >
                    <:start_icon><.icon name="hero-table-cells" class="size-[18px]" /></:start_icon>
                    XLSX
                  </.pp_button>
                  <.pp_button
                    variant="tonal"
                    href={~p"/export/vms.csv"}
                    target="_blank"
                    rel="noopener noreferrer"
                    id="dashboard-export-csv"
                    title="Download VirtualMachines as CSV"
                  >
                    <:start_icon>
                      <.icon name="hero-arrow-down-tray" class="size-[18px]" />
                    </:start_icon>
                    CSV
                  </.pp_button>
                </.pp_button_group>
                <.pp_button
                  phx-click="refresh"
                  id="dashboard-refresh"
                  title={"Also auto-refreshes every #{format_interval_label(auto_refresh_ms())}"}
                >
                  <:start_icon><.icon name="hero-arrow-path" class="size-[18px]" /></:start_icon>
                  Refresh
                </.pp_button>
              </div>
            </div>

            <div class="flex flex-wrap items-center justify-between gap-x-3 border-b border-pp-surface-variant">
              <.live_tabs
                id="kubevirt-dashboard-tabs"
                active={@active_tab}
                event="set_tab"
                tabs={dashboard_tab_defs()}
                class="min-w-0 flex-1"
              />
              <div
                id="dashboard-prometheus-nav-indicator"
                class="flex shrink-0 items-center py-2 ps-3 lg:ps-4"
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
                    <.section_title icon="hero-chart-bar-square">
                      Cluster overview
                      <.tab_heading_hint
                        id="dashboard-tab-overview-hint"
                        tip="Metrics and charts from a one-time cluster snapshot (VirtualMachines, VMIs, nodes, PVCs, storage classes, optional Prometheus). Use Refresh to reload data."
                      />
                    </.section_title>
                  </div>
                  <div
                    :if={data.cluster}
                    class="flex flex-wrap items-center gap-x-3 gap-y-1"
                  >
                    <span class="shrink-0 pp-label-medium text-pp-on-surface-variant">
                      Current context
                    </span>
                    <.pp_chip variant="input" id="dashboard-current-context" class="font-mono">
                      <:icon><.icon name="hero-user-circle" /></:icon>
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
                          "var(--color-pp-primary)"
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
                          "var(--color-pp-tertiary)"
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
                    <.section_title icon="hero-computer-desktop">
                      Virtual machines
                      <.tab_heading_hint
                        id="dashboard-tab-vms-hint"
                        tip="Each row is a VirtualMachine with live instance fields from the matching VMI (same namespace and name) when it exists."
                      />
                    </.section_title>
                  </div>
                  <%= if data.vm_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.vmi_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list VMIs — join columns will be empty ({vm_error_text(
                          data.vmi_error
                        )}).
                      </span>
                    </.banner>
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
                        pagination={@pagination["vms"]}
                        empty_label="No VirtualMachines found."
                        id_prefix="vm"
                      />
                    </div>
                  <% end %>
                  <%= if data.vmi_error == nil && data.vm_error == nil do %>
                    <% orphans = vmi_orphans_without_vm(data.vms, data.vmis) %>
                    <div :if={orphans != []} class="space-y-3 pt-4 border-t border-pp-outline-variant">
                      <.section_title tag="h3" icon="hero-cpu-chip">
                        VM instances without a VirtualMachine
                        <.tab_heading_hint
                          id="dashboard-tab-orphan-vmi-hint"
                          tip="Usually short-lived (for example during delete); same columns as the main instance view."
                        />
                      </.section_title>
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
                    <.section_title icon="hero-wifi">
                      VM network interfaces
                      <.tab_heading_hint
                        id="dashboard-tab-networks-hint"
                        tip="Declared on each VirtualMachine template (spec.template.spec.domain.devices.interfaces), with live MAC, IP, and guest interface name from the matching VMI when running."
                      />
                    </.section_title>
                  </div>
                  <%= if data.vm_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_network_interfaces_table
                      vms={data.vms}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
                      filters={@filters["networks"]}
                      sort={@sort["networks"]}
                      pagination={@pagination["networks"]}
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
                    <.section_title icon="hero-circle-stack">
                      VM disks &amp; volumes
                      <.tab_heading_hint
                        id="dashboard-tab-disks-hint"
                        tip="Block devices from spec.template.spec.domain.devices.disks linked to template volumes; size and storage class use DataVolume templates and cluster PVCs when resolvable."
                      />
                    </.section_title>
                  </div>
                  <%= if data.vm_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list VirtualMachines ({vm_error_text(data.vm_error)}).
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.vm_error == nil do %>
                    <.virtual_machine_disks_detail_table
                      vms={data.vms}
                      pvcs={List.wrap(data.pvcs)}
                      filters={@filters["disks"]}
                      sort={@sort["disks"]}
                      pagination={@pagination["disks"]}
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
                    <.section_title icon="hero-archive-box">
                      Storage classes
                      <.tab_heading_hint
                        id="dashboard-tab-storage-classes-hint"
                        tip="Cluster-scoped StorageClass objects from storage.k8s.io/v1. PVC counts use spec.storageClassName from all namespaces; PVCs with no class set are listed separately. Names on PVCs that do not match any listed class may be typos or removed classes."
                      />
                    </.section_title>
                  </div>
                  <%= if data.storage_class_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list StorageClasses ({vm_error_text(data.storage_class_error)}).
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.storage_class_error == nil do %>
                    <.storage_classes_table
                      storage_classes={List.wrap(data.storage_classes)}
                      pvcs={List.wrap(data.pvcs)}
                      filters={@filters["storage_classes"]}
                      sort={@sort["storage_classes"]}
                      pagination={@pagination["storage_classes"]}
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
                    <.section_title icon="hero-server-stack">
                      Nodes
                      <.tab_heading_hint
                        id="dashboard-tab-nodes-hint"
                        tip="Kubernetes Nodes from the cluster API (status.addresses, allocatable resources, conditions). CPU and memory % prefer metrics-server NodeMetrics; when that API is missing, values are taken from Prometheus node_exporter (same queries as the dashboard) when scrape targets match the node name, hostname, or internal IP. VMIs counts use VMI status.nodeName."
                      />
                    </.section_title>
                  </div>
                  <%= if data.node_error do %>
                    <.banner kind={:warning}>
                      <span>
                        Could not list Nodes ({vm_error_text(data.node_error)}).
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.metrics_error && not m.prometheus_ok? do %>
                    <.banner kind={:warning}>
                      <span>
                        metrics-server NodeMetrics is unavailable ({vm_error_text(data.metrics_error)}). {cluster_usage_prometheus_hint_text()}
                      </span>
                    </.banner>
                  <% end %>
                  <%= if data.node_error == nil do %>
                    <.nodes_table
                      nodes={List.wrap(data.nodes)}
                      vmis={if(data.vmi_error, do: [], else: data.vmis)}
                      node_metrics={List.wrap(data.node_metrics)}
                      prometheus_node_detail={m.prometheus_node_detail}
                      filters={@filters["nodes"]}
                      sort={@sort["nodes"]}
                      pagination={@pagination["nodes"]}
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
                  <.section_title icon="hero-squares-2x2">
                    Topology
                    <.tab_heading_hint
                      id="dashboard-tab-topology-hint"
                      tip="VMs are linked to cluster nodes using each VMI status.nodeName (matching VM and VMI name and namespace). Stopped VMs without a VMI appear under Unscheduled."
                    />
                  </.section_title>
                </div>
                <section
                  id="vm-topology-root"
                  data-vm-topology-root
                  class="rounded-pp-lg border border-pp-outline-variant bg-pp-surface-container-low overflow-hidden"
                  phx-hook="VmTopology"
                  data-topology={Jason.encode!(VmTopology.build(data))}
                >
                  <div class="flex flex-col xl:flex-row min-h-[min(78vh,820px)] max-h-[min(85vh,900px)]">
                    <aside class="w-full xl:w-64 shrink-0 border-b xl:border-b-0 xl:border-e border-pp-outline-variant p-4 space-y-6 bg-pp-surface-container">
                      <div>
                        <p class="pp-label-medium text-pp-on-surface-variant mb-2">
                          Legend
                        </p>
                        <ul class="pp-body-small space-y-2 text-pp-on-surface">
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
                      <.pp_select
                        id="vm-topology-layout"
                        label="Layout"
                        value="organic"
                        options={[{"Organic", "organic"}, {"Hierarchical", "hierarchical"}]}
                        data-topology-layout
                      />
                      <div>
                        <p class="pp-label-medium text-pp-on-surface-variant mb-2">
                          Actions
                        </p>
                        <div class="flex flex-wrap gap-2">
                          <.pp_button
                            variant="text"
                            size="xs"
                            data-topology-reset
                            id="vm-topology-reset"
                          >
                            <:start_icon>
                              <.icon name="hero-arrow-uturn-left" class="size-4" />
                            </:start_icon>
                            Reset view
                          </.pp_button>
                          <.pp_button
                            variant="outlined"
                            size="xs"
                            data-topology-fit
                            id="vm-topology-fit"
                          >
                            <:start_icon>
                              <.icon name="hero-arrows-pointing-out" class="size-4" />
                            </:start_icon>
                            Fit to screen
                          </.pp_button>
                        </div>
                      </div>
                      <div>
                        <p class="pp-label-medium text-pp-on-surface-variant mb-2">
                          Summary
                        </p>
                        <dl class="pp-body-small space-y-1.5 text-pp-on-surface">
                          <div class="flex justify-between gap-2">
                            <dt class="text-pp-on-surface-variant">Nodes</dt>
                            <dd class="font-mono tabular-nums" data-topology-summary-nodes>—</dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-pp-on-surface-variant">VMs</dt>
                            <dd class="font-mono tabular-nums" data-topology-summary-vms>—</dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-pp-on-surface-variant">Running</dt>
                            <dd
                              class="font-mono tabular-nums text-success"
                              data-topology-summary-running
                            >
                              —
                            </dd>
                          </div>
                          <div class="flex justify-between gap-2">
                            <dt class="text-pp-on-surface-variant">Stopped</dt>
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
                    <div class="flex-1 min-h-[min(52vh,560px)] min-w-0 bg-pp-surface relative">
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

  defp dashboard_heading(assigns) do
    ~H"""
    <.page_title eyebrow="Overview">
      KubeVirt Tools
      <:subtitle>Cluster-wide Virtualization Insights</:subtitle>
    </.page_title>
    """
  end

  attr :tip, :string,
    required: true,
    doc: "Shown in a rich tooltip on hover/focus, and to screen readers (aria-label)"

  attr :id, :string, required: true

  defp tab_heading_hint(assigns) do
    ~H"""
    <.pp_tooltip id={@id} title={@tip} variant="rich" placement="bottom" class="w-80 max-w-[80vw]">
      <span
        class={[
          "inline-flex shrink-0 cursor-help rounded-pp-full p-1 -m-1 pp-state-layer pp-focus-ring",
          "text-pp-on-surface-variant hover:text-pp-primary"
        ]}
        tabindex="0"
        aria-label={@tip}
      >
        <.icon name="hero-information-circle" class="size-5" />
      </span>
    </.pp_tooltip>
    """
  end

  attr :tab, :string, required: true
  attr :filters, :map, required: true
  attr :search_placeholder, :string, default: "Search by name…"

  attr :specs, :list,
    required: true,
    doc: "[%{field: \"phase\", label: \"Phase\", options: [\"Running\", ...]}, ...]"

  # MD3 filter bar: a search text field plus one menu per column filter. Each
  # menu's trigger shows the active value; picking an item pushes `set_filter`
  # (tab/field/value) and closes the menu.
  defp table_filter_bar(assigns) do
    active? = Enum.any?(assigns.filters, fn {_k, v} -> v != "" end)
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <div class="flex flex-wrap items-center gap-x-3 gap-y-2 py-2">
      <.pp_text_field
        id={"filter-search-#{@tab}"}
        name="value"
        label={@search_placeholder}
        value={Map.get(@filters, "search", "")}
        phx-keyup="set_filter"
        phx-value-tab={@tab}
        phx-value-field="search"
        phx-debounce="300"
        autocomplete="off"
        class="w-full sm:w-72"
      >
        <:start_adornment><.icon name="hero-magnifying-glass" class="size-6" /></:start_adornment>
      </.pp_text_field>
      <.pp_menu
        :for={spec <- @specs}
        id={"filter-menu-#{@tab}-#{spec.field}"}
        trigger_variant={if(Map.get(@filters, spec.field, "") == "", do: "outlined", else: "tonal")}
        class="max-h-80 overflow-y-auto"
      >
        <:trigger>
          {spec.label}<span :if={Map.get(@filters, spec.field, "") != ""}>: {Map.get(@filters, spec.field)}</span>
        </:trigger>
        <.pp_menu_item
          :for={opt <- ["" | spec.options]}
          selected={Map.get(@filters, spec.field, "") == opt}
          phx-click={
            JS.push("set_filter", value: %{tab: @tab, field: spec.field, value: opt})
            |> PhoenixPaper.Menu.close("filter-menu-#{@tab}-#{spec.field}")
          }
        >
          {if(opt == "", do: "All", else: opt)}
        </.pp_menu_item>
      </.pp_menu>
      <.pp_button
        :if={@active?}
        variant="text"
        phx-click="clear_filters"
        phx-value-tab={@tab}
        id={"filter-clear-#{@tab}"}
      >
        <:start_icon><.icon name="hero-x-mark" class="size-[18px]" /></:start_icon>
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

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :sub, :string, default: nil
  attr :title, :string, default: nil

  attr :highlight, :atom,
    values: [:neutral, :primary, :success, :danger, :warning],
    default: :neutral

  # KPI tile: an outlined MD3 card with a label-medium caption and the value
  # in headline-small, colored by `highlight`.
  defp stat_tile(assigns) do
    ~H"""
    <.pp_card id={@id} variant="outlined" class="min-w-0">
      <p class="pp-label-medium text-pp-on-surface-variant">{@label}</p>
      <p
        class={["mt-1 pp-headline-small tabular-nums break-words", highlight_class(@highlight)]}
        title={@title}
      >
        {@value}
      </p>
      <p :if={@sub} class="mt-0.5 pp-body-small text-pp-on-surface-variant">{@sub}</p>
    </.pp_card>
    """
  end

  defp highlight_class(:primary), do: tone_text_class(:ok)
  defp highlight_class(:success), do: tone_text_class(:ok)
  defp highlight_class(:danger), do: tone_text_class(:stopped)
  defp highlight_class(:warning), do: tone_text_class(:warning)
  defp highlight_class(:neutral), do: "text-pp-on-surface"

  attr :connected?, :boolean, required: true
  attr :url, :string, required: true

  defp prometheus_compact_indicator(assigns) do
    ~H"""
    <div
      class="inline-flex items-center gap-2 pp-label-medium text-pp-on-surface-variant"
      title={@url}
    >
      <span>Prometheus</span>
      <span class="relative flex size-3 shrink-0 items-center justify-center" aria-hidden="true">
        <span
          :if={@connected?}
          class="absolute size-2.5 rounded-pp-full bg-pp-primary/55 motion-safe:animate-ping"
        />
        <span class={[
          "relative size-2 rounded-pp-full",
          if(@connected?, do: "bg-pp-primary", else: "bg-app-warning")
        ]} />
      </span>
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
    ~H"""
    <%= if @overlay do %>
      <section
        id={@id}
        class="flex min-w-0 flex-col gap-2 rounded-pp-md border border-dashed border-pp-outline p-4"
      >
        <h3 class="pp-label-medium text-pp-on-surface-variant">{@label}</h3>
        <.banner kind={:warning} icon="hero-puzzle-piece" title="Prometheus not detected!">
          {@overlay}
        </.banner>
      </section>
    <% else %>
      <.stat_tile id={@id} label={@label} value={@value} sub={@sub} highlight={@highlight} />
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
    <.stat_tile id={@id} label={@label} value={@value} title={@title} sub={@hint} />
    """
  end

  attr :id, :string, required: true

  defp node_load_chart_placeholder(assigns) do
    ~H"""
    <.prometheus_placeholder
      id={@id}
      label="Node load distribution"
      height_class="h-[220px]"
      bars={[92, 58, 76, 40]}
    >
      {cluster_usage_prometheus_hint_text()}
    </.prometheus_placeholder>
    """
  end

  attr :id, :string, default: nil
  attr :label, :string, required: true
  attr :height_class, :string, required: true
  attr :bars, :list, required: true, doc: "widths (percent) of the dimmed placeholder bars"
  slot :inner_block, required: true

  # A chart-shaped card dimmed behind a warning banner, shown when the data
  # needs Prometheus and none was detected.
  defp prometheus_placeholder(assigns) do
    ~H"""
    <section
      id={@id}
      class="flex min-w-0 w-full flex-col gap-2 overflow-hidden rounded-pp-md border border-dashed border-pp-outline p-4"
    >
      <h3 class="pp-title-small text-pp-on-surface-variant shrink-0">{@label}</h3>
      <div class={["relative w-full min-w-0 overflow-hidden rounded-pp-sm", @height_class]}>
        <div class="absolute inset-0 flex flex-col justify-center gap-3.5 px-3 py-4 opacity-40 pointer-events-none">
          <div :for={width <- @bars} class="flex items-center gap-2">
            <div class="h-2.5 w-11 shrink-0 rounded-pp-xs bg-pp-surface-container-highest" />
            <div
              class="h-6 rounded-pp-xs bg-pp-surface-container-highest motion-safe:animate-pulse"
              style={"width: #{width}%"}
            />
          </div>
        </div>
        <div class="absolute inset-0 z-10 flex items-center justify-center p-2 sm:p-3">
          <.banner
            kind={:warning}
            icon="hero-puzzle-piece"
            title="Prometheus not detected!"
            class="max-h-full max-w-[min(100%,22rem)] overflow-y-auto pp-elevation-2"
          >
            {render_slot(@inner_block)}
          </.banner>
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
  attr :pagination, :map, required: true
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
      |> assign(:page, paginate(rows, assigns.pagination))
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
      <.pp_table_container class="!overflow-visible">
        <div class="overflow-x-auto rounded-t-pp-md">
          <.pp_table>
            <.pp_table_head>
              <.pp_table_row>
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
              </.pp_table_row>
            </.pp_table_head>
            <.pp_table_body>
              <.pp_table_row :if={@rows == []}>
                <.pp_table_cell colspan="9" align="center" class="py-8 text-pp-on-surface-variant">
                  {if(@items == [], do: @empty_label, else: "No VMs match the current filters.")}
                </.pp_table_cell>
              </.pp_table_row>
              <%= for {row, i} <- Enum.with_index(@page.rows) do %>
                <.pp_table_row
                  id={"#{@id_prefix}-row-#{i}"}
                  class="cursor-pointer"
                  phx-click={JS.navigate(~p"/vms/#{row.namespace}/#{row.name}")}
                >
                  <.pp_table_cell class="whitespace-nowrap">
                    <div class="font-medium">{row.name}</div>
                    <div class="font-mono pp-body-small text-pp-on-surface-variant">
                      {row.namespace}
                    </div>
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <.status_chip tone={row.phase_tone}>{row.phase}</.status_chip>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="tabular-nums font-medium"
                    title={
                      if(row.usage_unavailable?,
                        do: "Usage unavailable — no metrics-server data for this VM's pod yet",
                        else: "sockets × cores × threads"
                      )
                    }
                  >
                    {row.cpu_display}
                    <span
                      :if={row.cpu_pct}
                      class={["ml-1", tone_text_class(usage_pct_tone(row.cpu_pct))]}
                    >
                      {row.cpu_pct}%
                    </span>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="font-mono text-pp-on-surface-variant"
                    title={
                      if(row.usage_unavailable?,
                        do: "Usage unavailable — no metrics-server data for this VM's pod yet",
                        else: nil
                      )
                    }
                  >
                    {row.mem_display}
                    <span
                      :if={row.mem_pct}
                      class={["ml-1", tone_text_class(usage_pct_tone(row.mem_pct))]}
                    >
                      {row.mem_pct}%
                    </span>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="font-mono text-pp-on-surface-variant max-w-[10rem] truncate"
                    title={row.node}
                  >
                    {row.node}
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="font-mono text-pp-on-surface-variant max-w-[9rem] truncate"
                    title={row.ip}
                  >
                    {row.ip}
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <span :if={row.agent_connected?} class="font-medium text-pp-primary">
                      Running
                    </span>
                    <span :if={!row.agent_connected?} class="font-medium text-stopped">
                      Not running
                    </span>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="text-pp-on-surface-variant max-w-[10rem] truncate"
                    title={row.os}
                  >
                    {row.os}
                  </.pp_table_cell>
                  <.pp_table_cell class="text-pp-on-surface-variant whitespace-nowrap">
                    {row.created}
                  </.pp_table_cell>
                </.pp_table_row>
              <% end %>
            </.pp_table_body>
          </.pp_table>
        </div>
        <.table_pager id="vms-pagination" key="vms" page={@page} />
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
      <.pp_table>
        <.pp_table_head>
          <.pp_table_row>
            <.pp_table_cell variant="head">Namespace</.pp_table_cell>
            <.pp_table_cell variant="head">Name</.pp_table_cell>
            <.pp_table_cell variant="head">Phase</.pp_table_cell>
            <.pp_table_cell variant="head">Node</.pp_table_cell>
            <.pp_table_cell variant="head">CPU (guest)</.pp_table_cell>
            <.pp_table_cell variant="head">Memory</.pp_table_cell>
            <.pp_table_cell variant="head">IP</.pp_table_cell>
            <.pp_table_cell variant="head">Ready</.pp_table_cell>
            <.pp_table_cell variant="head">Created</.pp_table_cell>
          </.pp_table_row>
        </.pp_table_head>
        <.pp_table_body>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <.pp_table_row id={"#{@id_prefix}-row-#{i}"}>
              <.pp_table_cell class="font-mono whitespace-nowrap">
                {vm_meta(item, :namespace)}
              </.pp_table_cell>
              <.pp_table_cell class="font-medium whitespace-nowrap">
                {vm_meta(item, :name)}
              </.pp_table_cell>
              <.pp_table_cell>
                <.status_chip tone={phase_tone(vmi_phase(item))}>{vmi_phase(item)}</.status_chip>
              </.pp_table_cell>
              <.pp_table_cell
                class="font-mono text-pp-on-surface-variant max-w-[10rem] truncate"
                title={vmi_scheduling_node_name(item)}
              >
                {vmi_scheduling_node_name(item)}
              </.pp_table_cell>
              <.pp_table_cell class="tabular-nums">{vmi_spec_cpu_cores(item)}</.pp_table_cell>
              <.pp_table_cell class="font-mono text-pp-on-surface-variant">
                {vmi_spec_memory_guest(item)}
              </.pp_table_cell>
              <.pp_table_cell
                class="font-mono text-pp-on-surface-variant max-w-[9rem] truncate"
                title={vmi_primary_ip(item)}
              >
                {vmi_primary_ip(item)}
              </.pp_table_cell>
              <.pp_table_cell>{vmi_ready_label(item)}</.pp_table_cell>
              <.pp_table_cell class="text-pp-on-surface-variant whitespace-nowrap">
                {vm_meta(item, :created)}
              </.pp_table_cell>
            </.pp_table_row>
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
  attr :pagination, :map, required: true
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
      |> assign(:page, paginate(rows, assigns.pagination))
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
      <.pp_table_container class="!overflow-visible">
        <div class="overflow-x-auto rounded-t-pp-md">
          <.pp_table>
            <.pp_table_head>
              <.pp_table_row>
                <.sortable_th tab="networks" field="vm" sort={@sort}>VM</.sortable_th>
                <.sortable_th tab="networks" field="interface" sort={@sort}>Interface</.sortable_th>
                <.sortable_th tab="networks" field="binding" sort={@sort}>Binding</.sortable_th>
                <.sortable_th tab="networks" field="ips" sort={@sort}>IP addresses</.sortable_th>
                <.sortable_th tab="networks" field="vmi_phase" sort={@sort}>VMI phase</.sortable_th>
              </.pp_table_row>
            </.pp_table_head>
            <.pp_table_body>
              <.pp_table_row :if={@rows == []}>
                <.pp_table_cell colspan="5" align="center" class="py-8 text-pp-on-surface-variant">
                  {if(@all_rows_empty?,
                    do: "No network interfaces defined on any VirtualMachine.",
                    else: "No interfaces match the current filters."
                  )}
                </.pp_table_cell>
              </.pp_table_row>
              <%= for {row, i} <- Enum.with_index(@page.rows) do %>
                <.pp_table_row
                  id={"#{@id_prefix}-row-#{i}"}
                  class="cursor-pointer"
                  phx-click={
                    JS.navigate(~p"/networks/#{row.namespace}/#{row.vm_name}/#{row.iface_name}")
                  }
                >
                  <.pp_table_cell class="whitespace-nowrap">
                    <div class="font-medium">{row.vm_name}</div>
                    <div class="font-mono pp-body-small text-pp-on-surface-variant">
                      {row.namespace}
                    </div>
                  </.pp_table_cell>
                  <.pp_table_cell class="font-mono text-pp-on-surface-variant">
                    {row.iface_name}
                  </.pp_table_cell>
                  <.pp_table_cell class="whitespace-nowrap">{row.binding}</.pp_table_cell>
                  <.pp_table_cell
                    class="font-mono text-pp-on-surface-variant max-w-[14rem] truncate"
                    title={row.ips}
                  >
                    {row.ips}
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <.status_chip tone={phase_tone(row.vmi_phase)}>{row.vmi_phase}</.status_chip>
                  </.pp_table_cell>
                </.pp_table_row>
              <% end %>
            </.pp_table_body>
          </.pp_table>
        </div>
        <.table_pager id="networks-pagination" key="networks" page={@page} />
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
  attr :pagination, :map, required: true
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
      |> assign(:page, paginate(rows, assigns.pagination))
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
      <.pp_table_container class="!overflow-visible">
        <div class="overflow-x-auto rounded-t-pp-md">
          <.pp_table>
            <.pp_table_head>
              <.pp_table_row>
                <.sortable_th tab="disks" field="vm" sort={@sort}>VM</.sortable_th>
                <.sortable_th tab="disks" field="disk" sort={@sort}>Disk</.sortable_th>
                <.sortable_th tab="disks" field="volume_kind" sort={@sort}>Volume kind</.sortable_th>
                <.sortable_th tab="disks" field="size" sort={@sort}>Size</.sortable_th>
                <.sortable_th tab="disks" field="storage_class" sort={@sort}>
                  Storage class
                </.sortable_th>
                <.sortable_th tab="disks" field="pvc_phase" sort={@sort}>PVC phase</.sortable_th>
              </.pp_table_row>
            </.pp_table_head>
            <.pp_table_body>
              <.pp_table_row :if={@rows == []}>
                <.pp_table_cell colspan="6" align="center" class="py-8 text-pp-on-surface-variant">
                  {if(@all_rows_empty?,
                    do: "No disks defined on any VirtualMachine.",
                    else: "No disks match the current filters."
                  )}
                </.pp_table_cell>
              </.pp_table_row>
              <%= for {row, i} <- Enum.with_index(@page.rows) do %>
                <.pp_table_row
                  id={"#{@id_prefix}-row-#{i}"}
                  class="cursor-pointer"
                  phx-click={JS.navigate(~p"/disks/#{row.namespace}/#{row.vm_name}/#{row.disk_name}")}
                >
                  <.pp_table_cell class="whitespace-nowrap">
                    <div class="font-medium">{row.vm_name}</div>
                    <div class="font-mono pp-body-small text-pp-on-surface-variant">
                      {row.namespace}
                    </div>
                  </.pp_table_cell>
                  <.pp_table_cell class="font-mono text-pp-on-surface-variant">
                    {row.disk_name}
                  </.pp_table_cell>
                  <.pp_table_cell class="whitespace-nowrap">{row.volume_kind}</.pp_table_cell>
                  <.pp_table_cell class="tabular-nums whitespace-nowrap">{row.size}</.pp_table_cell>
                  <.pp_table_cell class="max-w-[8rem] truncate" title={row.storage_class}>
                    {row.storage_class}
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <.status_chip tone={pvc_phase_tone(row.pvc_phase)}>{row.pvc_phase}</.status_chip>
                  </.pp_table_cell>
                </.pp_table_row>
              <% end %>
            </.pp_table_body>
          </.pp_table>
        </div>
        <.table_pager id="disks-pagination" key="disks" page={@page} />
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
  attr :pagination, :map, required: true
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
      |> assign(:page, paginate(rows, assigns.pagination))
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
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 pp-body-medium text-pp-on-surface-variant mb-2">
      <span>
        <span class="pp-title-small text-pp-on-surface tabular-nums">
          {length(@storage_classes)}
        </span>
        storage class{if length(@storage_classes) == 1, do: "", else: "es"}
      </span>
      <span :if={@unset_count > 0}>
        <span class="pp-title-small text-pp-on-surface tabular-nums">{@unset_count}</span>
        PVC{if @unset_count == 1, do: "", else: "s"} with no storageClassName
      </span>
    </div>
    <div class="space-y-2">
      <.table_filter_bar tab="storage_classes" filters={@filters} specs={@filter_specs} />
      <.pp_table_container class="!overflow-visible">
        <div class="overflow-x-auto rounded-t-pp-md">
          <.pp_table>
            <.pp_table_head>
              <.pp_table_row>
                <.sortable_th tab="storage_classes" field="name" sort={@sort}>Name</.sortable_th>
                <.sortable_th tab="storage_classes" field="default" sort={@sort}>
                  Default
                </.sortable_th>
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
              </.pp_table_row>
            </.pp_table_head>
            <.pp_table_body>
              <.pp_table_row :if={@rows == []}>
                <.pp_table_cell colspan="4" align="center" class="py-8 text-pp-on-surface-variant">
                  {if(@all_rows_empty?,
                    do: "No StorageClass objects returned from the API.",
                    else: "No storage classes match the current filters."
                  )}
                </.pp_table_cell>
              </.pp_table_row>
              <%= for {row, i} <- Enum.with_index(@page.rows) do %>
                <.pp_table_row
                  id={"#{@id_prefix}-row-#{i}"}
                  class="cursor-pointer"
                  phx-click={JS.navigate(~p"/storage_classes/#{row.name}")}
                >
                  <.pp_table_cell class="font-mono font-medium whitespace-nowrap">
                    {row.name}
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <%= if row.default? do %>
                      <.status_chip icon="hero-star-mini" selected>default</.status_chip>
                    <% else %>
                      <span class="text-pp-on-surface-variant">—</span>
                    <% end %>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="font-mono text-pp-on-surface-variant max-w-[14rem] truncate"
                    title={row.provisioner}
                  >
                    {row.provisioner}
                  </.pp_table_cell>
                  <.pp_table_cell class="tabular-nums font-medium">{row.pvc_count}</.pp_table_cell>
                </.pp_table_row>
              <% end %>
            </.pp_table_body>
          </.pp_table>
        </div>
        <.table_pager id="storage_classes-pagination" key="storage_classes" page={@page} />
      </.pp_table_container>
    </div>
    <.banner
      :if={@orphan_refs != []}
      kind={:warning}
      title="PVCs reference unknown storage classes"
      class="mt-3"
      id="dashboard-storage-class-orphan-pvcs"
    >
      These names appear on PVCs but do not match any listed StorageClass:
      <span class="font-mono">{orphan_storage_class_refs_pretty(@orphan_refs)}</span>
    </.banner>
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
  attr :pagination, :map, required: true
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
        "status" => & &1.status,
        "role" => & &1.role,
        "vmis" => & &1.vmi_count,
        "cpu" => &pct_sort_value(&1.cpu_pct),
        "mem" => &pct_sort_value(&1.mem_pct),
        "os" => & &1.os_image
      })

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:page, paginate(rows, assigns.pagination))
      |> assign(:all_rows_empty?, all_rows == [])
      |> assign(
        :filter_specs,
        [
          %{field: "status", label: "Status", options: distinct_present(all_rows, & &1.status)},
          %{field: "role", label: "Role", options: distinct_present(all_rows, & &1.role)},
          %{field: "os", label: "OS", options: distinct_present(all_rows, & &1.os_image)}
        ]
      )

    ~H"""
    <div class="space-y-2">
      <.table_filter_bar tab="nodes" filters={@filters} specs={@filter_specs} />
      <.pp_table_container class="!overflow-visible">
        <div class="overflow-x-auto rounded-t-pp-md">
          <.pp_table>
            <.pp_table_head>
              <.pp_table_row>
                <.sortable_th tab="nodes" field="name" sort={@sort}>Name</.sortable_th>
                <.sortable_th
                  tab="nodes"
                  field="status"
                  sort={@sort}
                  title="As kubectl get nodes: the Ready condition, plus SchedulingDisabled when cordoned"
                >
                  Status
                </.sortable_th>
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
              </.pp_table_row>
            </.pp_table_head>
            <.pp_table_body>
              <.pp_table_row :if={@rows == []}>
                <.pp_table_cell colspan="7" align="center" class="py-8 text-pp-on-surface-variant">
                  {if(@all_rows_empty?,
                    do: "No nodes returned from the API.",
                    else: "No nodes match the current filters."
                  )}
                </.pp_table_cell>
              </.pp_table_row>
              <%= for {row, i} <- Enum.with_index(@page.rows) do %>
                <.pp_table_row
                  id={"#{@id_prefix}-row-#{i}"}
                  class="cursor-pointer"
                  title={row.scheduling_hint}
                  phx-click={JS.navigate(~p"/nodes/#{row.name}")}
                >
                  <.pp_table_cell class="font-mono font-medium whitespace-nowrap">
                    {row.name}
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <.status_chip tone={node_status_tone(row.status)}>{row.status}</.status_chip>
                  </.pp_table_cell>
                  <.pp_table_cell>
                    <.status_chip class="font-mono">{row.role}</.status_chip>
                  </.pp_table_cell>
                  <.pp_table_cell
                    class="text-pp-on-surface-variant max-w-[12rem] truncate"
                    title={row.os_image}
                  >
                    {row.os_image}
                  </.pp_table_cell>
                  <.pp_table_cell class="tabular-nums font-medium">{row.vmi_count}</.pp_table_cell>
                  <.pp_table_cell class="tabular-nums">{row.cpu_pct}</.pp_table_cell>
                  <.pp_table_cell class="tabular-nums">{row.mem_pct}</.pp_table_cell>
                </.pp_table_row>
              <% end %>
            </.pp_table_body>
          </.pp_table>
        </div>
        <.table_pager id="nodes-pagination" key="nodes" page={@page} />
      </.pp_table_container>
    </div>
    """
  end

  defp node_row_matches_filters?(row, filters) do
    matches_search?(filters["search"], row.name) and
      matches_field?(filters["status"], row.status) and
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
