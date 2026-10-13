defmodule KubevirtToolsWeb.NodeShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.DashboardCharts
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
  alias KubevirtToolsWeb.PaginationComponents
  alias KubevirtTools.KubeVirt
  alias KubevirtTools.PrometheusClient

  # Cadence for the periodic full-page refresh and the Prometheus history
  # re-query, configurable via POLL_INTERVAL_MS (shared with the dashboard's
  # own auto-refresh and the VM show page).
  defp poll_ms, do: KubevirtTools.EnvConfig.int("POLL_INTERVAL_MS", 60_000)
  # Trailing window queried from Prometheus for the live usage charts.
  @history_window_s 1800
  @history_step_s 30

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Node: #{name}")
      |> assign(:name, name)
      |> assign(:pagination, PaginationComponents.new(["vmis"]))

    if connected?(socket), do: Process.send_after(self(), :poll_usage, poll_ms())

    {:ok,
     socket
     |> assign_async(:node_detail, fn -> load_node_detail(token, name) end)
     |> assign_async(:usage_history, fn -> load_usage_history(token, name) end)}
  end

  @impl true
  def handle_info(:poll_usage, socket) do
    Process.send_after(self(), :poll_usage, poll_ms())
    token = socket.assigns.kubeconfig_token
    name = socket.assigns.name

    {:noreply,
     socket
     |> assign_async(:node_detail, fn -> load_node_detail(token, name) end)
     |> assign_async(:usage_history, fn -> load_usage_history(token, name) end)}
  end

  # Metrics-server only here (no Prometheus fallback, unlike the dashboard's Nodes
  # tab) — this page doesn't hold the dashboard LiveView's PubSub-fed Prometheus
  # snapshot, and CPU/Mem % is a secondary field on a detail page.
  defp load_node_detail(token, name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, nodes} <- ClusterInventory.list_nodes(conn),
         {:ok, vmis} <- KubeVirt.list_virtual_machine_instances(conn),
         {node_metrics, _metrics_err} <- safe_list(&ClusterMetrics.list_node_metrics/1, conn) do
      case Enum.find(nodes, &(get_in(&1, ["metadata", "name"]) == name)) do
        nil ->
          {:ok, %{node_detail: %{found?: false}}}

        node ->
          merged = nodes_merged_usage_map([node], node_metrics, %{})
          [row] = kubernetes_nodes_table_rows([node], vmis, merged)

          node_vmis =
            vmis
            |> Enum.filter(&(vmi_scheduling_node_name(&1) == name))
            |> Enum.sort_by(&{vm_meta(&1, :namespace), vm_meta(&1, :name)})

          {:ok, %{node_detail: %{found?: true, row: row, vmis: node_vmis}}}
      end
    else
      :error -> {:error, :invalid_session}
      {:error, reason} -> {:error, K8sSafeError.user_facing(reason)}
    end
  end

  defp safe_list(fun, conn) do
    case fun.(conn) do
      {:ok, items} -> {items, nil}
      {:error, reason} -> {[], reason}
    end
  end

  # Runs independently of load_node_detail/2 (its own assign_async, own Task) so a
  # slow or unreachable Prometheus never delays the rest of the page. Live usage
  # charts require Prometheus scraping node_exporter (same metrics the dashboard's
  # Nodes tab falls back to when metrics-server is unavailable) — any failure here
  # (unreachable, no matching series) is encoded as {:error, reason} *inside* the
  # ok payload so it never triggers the generic :failed slot.
  defp load_usage_history(token, name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, nodes} <- ClusterInventory.list_nodes(conn) do
      case Enum.find(nodes, &(get_in(&1, ["metadata", "name"]) == name)) do
        nil ->
          {:ok, %{usage_history: {:error, :not_found}}}

        node ->
          candidates = node_prometheus_match_labels(node)
          now_s = System.system_time(:second)
          start_s = now_s - @history_window_s

          {:ok,
           %{
             usage_history:
               PrometheusClient.node_usage_range(candidates, start_s, now_s, @history_step_s)
           }}
      end
    else
      :error -> {:ok, %{usage_history: {:error, :invalid_session}}}
      {:error, reason} -> {:ok, %{usage_history: {:error, reason}}}
    end
  end

  @impl true
  def handle_event(event, params, socket) when event in ["set_page", "set_per_page"] do
    {:noreply,
     update(socket, :pagination, &PaginationComponents.handle_pagination_event(&1, event, params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-full min-w-0">
        <.pp_breadcrumbs id="node-breadcrumbs">
          <:item navigate={~p"/dashboard"}>Dashboard</:item>
          <:item navigate={~p"/dashboard?tab=nodes"}>Nodes</:item>
          <:item>{@name}</:item>
        </.pp_breadcrumbs>

        <.async_result :let={data} assign={@node_detail}>
          <:loading>
            <.loading_card label="Loading node…" />
          </:loading>
          <:failed :let={_failure}>
            <.banner kind={:error}>
              Could not load this node. Try refreshing or signing in again.
            </.banner>
          </:failed>

          <.banner :if={!data.found?} kind={:warning}>
            Node <span class="font-mono">{@name}</span> was not found — it may have been removed.
          </.banner>

          <div :if={data.found?} class="space-y-6">
            <.page_title icon="hero-server-stack">
              {data.row.name}
              <:chips>
                <.status_chip tone={node_status_tone(data.row.status)}>
                  {data.row.status}
                </.status_chip>
              </:chips>
            </.page_title>

            <.list id="node-details">
              <:item title="Role">{data.row.role}</:item>
              <:item title="OS">{data.row.os_image}</:item>
              <:item title="Scheduling">{data.row.scheduling}</:item>
              <:item title="VMIs">{data.row.vmi_count}</:item>
              <:item title="CPU %">{data.row.cpu_pct}</:item>
              <:item title="Memory %">{data.row.mem_pct}</:item>
              <:item title="Internal IP">{data.row.internal_ip}</:item>
              <:item title="External IP">{data.row.external_ip}</:item>
              <:item title="CPU (allocatable)">{data.row.cpu_alloc}</:item>
              <:item title="Memory (allocatable)">{data.row.mem_alloc}</:item>
              <:item title="Max pods">{data.row.pods_alloc}</:item>
              <:item title="Kubelet">{data.row.kubelet}</:item>
              <:item title="OS / arch">{data.row.os_arch}</:item>
              <:item title="Container runtime">{data.row.runtime}</:item>
            </.list>

            <% overlay_message =
              "Requires Prometheus scraping node_exporter — set PROMETHEUS_URL (see README)"

            {cpu_points, mem_points, overlay} =
              case @usage_history do
                %{ok?: true, result: {:ok, %{cpu_points: c, mem_points: m}}}
                when length(c) >= 2 ->
                  {c, m, nil}

                %{ok?: true} ->
                  {[], [], overlay_message}

                %{loading: l} when l not in [nil, false] ->
                  {[], [], "Checking Prometheus…"}

                _ ->
                  {[], [], overlay_message}
              end %>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3 md:gap-4">
              <.apex_chart
                id={"node-cpu-usage-chart-#{@name}"}
                title={"CPU usage (last 30 min, refreshes every #{format_interval_label(poll_ms())})"}
                height="150px"
                opts={DashboardCharts.usage_area_chart(cpu_points, name: "CPU %")}
                dependency_overlay={overlay}
              />
              <.apex_chart
                id={"node-mem-usage-chart-#{@name}"}
                title={"Memory usage (last 30 min, refreshes every #{format_interval_label(poll_ms())})"}
                height="150px"
                opts={
                  DashboardCharts.usage_area_chart(mem_points,
                    name: "Memory %",
                    color: "var(--color-pp-tertiary)"
                  )
                }
                dependency_overlay={overlay}
              />
            </div>

            <div class="space-y-3">
              <.section_title icon="hero-cpu-chip">VMs on this node</.section_title>
              <.pp_table_container class="!overflow-visible">
                <div class="overflow-x-auto rounded-t-pp-md">
                  <.pp_table>
                    <.pp_table_head>
                      <.pp_table_row>
                        <.pp_table_cell variant="head">Namespace</.pp_table_cell>
                        <.pp_table_cell variant="head">Name</.pp_table_cell>
                        <.pp_table_cell variant="head">Phase</.pp_table_cell>
                        <.pp_table_cell variant="head">Agent</.pp_table_cell>
                      </.pp_table_row>
                    </.pp_table_head>
                    <.pp_table_body>
                      <.pp_table_row :if={data.vmis == []}>
                        <.pp_table_cell
                          colspan="4"
                          align="center"
                          class="py-8 text-pp-on-surface-variant"
                        >
                          No VMIs scheduled on this node.
                        </.pp_table_cell>
                      </.pp_table_row>
                      <.pp_table_row
                        :for={vmi <- paginate(data.vmis, @pagination["vmis"]).rows}
                        class="cursor-pointer"
                        phx-click={
                          JS.navigate(~p"/vms/#{vm_meta(vmi, :namespace)}/#{vm_meta(vmi, :name)}")
                        }
                      >
                        <.pp_table_cell class="font-mono text-pp-on-surface-variant">
                          {vm_meta(vmi, :namespace)}
                        </.pp_table_cell>
                        <.pp_table_cell class="font-mono font-medium">
                          {vm_meta(vmi, :name)}
                        </.pp_table_cell>
                        <.pp_table_cell>
                          <.status_chip tone={phase_tone(vmi_phase(vmi))}>
                            {vmi_phase(vmi)}
                          </.status_chip>
                        </.pp_table_cell>
                        <.pp_table_cell>
                          <.icon
                            :if={vmi_agent_connected?(vmi)}
                            name="hero-command-line"
                            class="size-5 text-pp-primary"
                          />
                          <span :if={!vmi_agent_connected?(vmi)} class="text-pp-on-surface-variant">
                            —
                          </span>
                        </.pp_table_cell>
                      </.pp_table_row>
                    </.pp_table_body>
                  </.pp_table>
                </div>
                <.table_pager
                  id="vmis-pagination"
                  key="vmis"
                  page={paginate(data.vmis, @pagination["vmis"])}
                />
              </.pp_table_container>
            </div>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
