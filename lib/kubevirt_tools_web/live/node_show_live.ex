defmodule KubevirtToolsWeb.NodeShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.ClusterMetrics
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
  alias KubevirtTools.KubeVirt

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Node: #{name}")
      |> assign(:name, name)

    {:ok, assign_async(socket, :node_detail, fn -> load_node_detail(token, name) end)}
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
