defmodule KubevirtToolsWeb.NodeShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.DashboardCharts
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
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
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-full min-w-0">
        <.link
          navigate={~p"/dashboard?tab=nodes"}
          class="link link-hover text-sm text-base-content/60"
        >
          &larr; Back to Nodes
        </.link>

        <.async_result :let={data} assign={@node_detail}>
          <:loading>
            <div class="flex items-center gap-3 rounded-xl border border-base-300/70 bg-base-200/40 px-5 py-12 text-base-content/70">
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading node…</span>
            </div>
          </:loading>
          <:failed :let={_failure}>
            <div class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
              <span>Could not load this node. Try refreshing or signing in again.</span>
            </div>
          </:failed>

          <div :if={!data.found?} class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
            <span>
              Node <span class="font-mono">{@name}</span> was not found — it may have been removed.
            </span>
          </div>

          <div :if={data.found?} class="space-y-6">
            <div>
              <h1 class="text-2xl font-semibold tracking-tight flex items-center gap-3">
                <.icon name="hero-server-stack" class="size-6 text-primary" /> {data.row.name}
                <span :if={data.row.is_ready} class="badge badge-sm badge-success">Ready</span>
                <span :if={!data.row.is_ready} class="badge badge-sm badge-error">Not ready</span>
              </h1>
            </div>

            <div class="rounded-xl border border-base-300/70 bg-base-100 shadow-sm p-4">
              <.list>
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
            </div>

            <%
              overlay_message =
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
                end
            %>
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
                    color: "var(--color-info)"
                  )
                }
                dependency_overlay={overlay}
              />
            </div>

            <div class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-cpu-chip" class="size-5 text-primary" /> VMs on this node
              </h2>
              <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
                <table class="table table-sm">
                  <thead class="bg-base-200/60 text-base-content/80">
                    <tr>
                      <th>Namespace</th>
                      <th>Name</th>
                      <th>Phase</th>
                      <th>Agent</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :if={data.vmis == []}>
                      <td colspan="4" class="text-center text-base-content/50 py-6">
                        No VMIs scheduled on this node.
                      </td>
                    </tr>
                    <tr :for={vmi <- data.vmis} class="hover:bg-base-200/40">
                      <td class="font-mono text-xs">{vm_meta(vmi, :namespace)}</td>
                      <td class="font-mono text-xs font-medium">{vm_meta(vmi, :name)}</td>
                      <td class="text-xs">
                        <span class="badge badge-sm badge-ghost">{vmi_phase(vmi)}</span>
                      </td>
                      <td class="text-xs">
                        <.icon
                          :if={vmi_agent_connected?(vmi)}
                          name="hero-command-line"
                          class="size-4 text-info"
                        />
                        <span :if={!vmi_agent_connected?(vmi)} class="text-base-content/40">—</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
