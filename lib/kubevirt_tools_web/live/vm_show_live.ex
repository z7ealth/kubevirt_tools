defmodule KubevirtToolsWeb.VmShowLive do
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
  # own auto-refresh).
  defp poll_ms, do: KubevirtTools.EnvConfig.int("POLL_INTERVAL_MS", 60_000)
  # Trailing window queried from Prometheus for the live usage charts.
  @history_window_s 1800
  @history_step_s 30

  @impl true
  def mount(%{"namespace" => ns, "name" => name}, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "VM: #{name}")
      |> assign(:namespace, ns)
      |> assign(:name, name)

    if connected?(socket), do: Process.send_after(self(), :poll_usage, poll_ms())

    {:ok,
     socket
     |> assign_async(:vm_detail, fn -> load_vm_detail(token, ns, name) end)
     |> assign_async(:usage_history, fn -> load_usage_history(token, ns, name) end)}
  end

  @impl true
  def handle_info(:poll_usage, socket) do
    Process.send_after(self(), :poll_usage, poll_ms())
    token = socket.assigns.kubeconfig_token
    ns = socket.assigns.namespace
    name = socket.assigns.name

    {:noreply,
     socket
     |> assign_async(:vm_detail, fn -> load_vm_detail(token, ns, name) end)
     |> assign_async(:usage_history, fn -> load_usage_history(token, ns, name) end)}
  end

  defp load_vm_detail(token, ns, name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, vms} <- KubeVirt.list_virtual_machines(conn),
         {:ok, vmis} <- KubeVirt.list_virtual_machine_instances(conn),
         {:ok, pvcs} <- ClusterInventory.list_pvcs(conn) do
      case Enum.find(vms, &matches?(&1, ns, name)) do
        nil ->
          {:ok, %{vm_detail: %{found?: false}}}

        vm ->
          vmi = Enum.find(vmis, &matches?(&1, ns, name))
          {virt_launcher_pods, _} = safe_list(&ClusterInventory.list_virt_launcher_pods/1, conn)
          {pod_metrics, _} = safe_list(&ClusterMetrics.list_pod_metrics/1, conn)
          usage = ClusterMetrics.vm_resource_usage(vm, virt_launcher_pods, pod_metrics)

          {:ok,
           %{
             vm_detail: %{
               found?: true,
               vm: vm,
               vmi: vmi,
               usage: usage,
               network_rows: virtual_machine_network_interface_rows([vm], List.wrap(vmi)),
               disk_rows: virtual_machine_disk_detail_rows([vm], pvcs)
             }
           }}
      end
    else
      :error -> {:error, :invalid_session}
      {:error, reason} -> {:error, K8sSafeError.user_facing(reason)}
    end
  end

  # Runs independently of load_vm_detail/3 (its own assign_async, own Task) so a
  # slow or unreachable Prometheus never delays the rest of the page. Live usage
  # charts require Prometheus scraping standard cAdvisor container metrics for
  # the VM's virt-launcher pod (no KubeVirt-specific exporter needed) — any
  # failure here (unreachable, no pod yet, no matching series) is encoded as
  # {:error, reason} *inside* the ok payload so it never triggers the generic
  # :failed slot, and resolves fast since the Prometheus HTTP calls disable retry.
  defp load_usage_history(token, ns, name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, vms} <- KubeVirt.list_virtual_machines(conn),
         {:ok, vmis} <- KubeVirt.list_virtual_machine_instances(conn) do
      case Enum.find(vms, &matches?(&1, ns, name)) do
        nil ->
          {:ok, %{usage_history: {:error, :not_found}}}

        vm ->
          vmi = Enum.find(vmis, &matches?(&1, ns, name))
          {virt_launcher_pods, _} = safe_list(&ClusterInventory.list_virt_launcher_pods/1, conn)
          {:ok, %{usage_history: fetch_usage_history(vm, vmi, virt_launcher_pods)}}
      end
    else
      :error -> {:ok, %{usage_history: {:error, :invalid_session}}}
      {:error, reason} -> {:ok, %{usage_history: {:error, reason}}}
    end
  end

  defp fetch_usage_history(vm, vmi, virt_launcher_pods) do
    case ClusterMetrics.find_virt_launcher_pod(vm, virt_launcher_pods) do
      nil ->
        {:error, :no_pod}

      pod ->
        pod_ns = get_in(pod, ["metadata", "namespace"])
        pod_name = get_in(pod, ["metadata", "name"])
        {_cores, _sockets, guest_cpu_total} = virtual_machine_cpu_topology_cells(vm, vmi)
        vcpu_count = String.to_integer(guest_cpu_total)
        mem_total_bytes = vm |> memory_for_vm_row(vmi) |> ClusterMetrics.quantity_to_bytes()

        now_s = System.system_time(:second)
        start_s = now_s - @history_window_s

        PrometheusClient.vm_usage_range(
          pod_ns,
          pod_name,
          vcpu_count,
          mem_total_bytes,
          start_s,
          now_s,
          @history_step_s
        )
    end
  end

  defp matches?(item, ns, name),
    do: vm_meta(item, :namespace) == ns and vm_meta(item, :name) == name

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
        <.link navigate={~p"/dashboard?tab=vms"} class="text-sm text-pp-primary hover:underline">
          &larr; Back to VMs
        </.link>

        <.async_result :let={data} assign={@vm_detail}>
          <:loading>
            <.pp_paper
              elevation={0}
              class="flex items-center gap-3 border border-pp-outline/20 bg-pp-surface-variant/40 px-5 py-12 text-pp-on-surface/70"
            >
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading VM…</span>
            </.pp_paper>
          </:loading>
          <:failed :let={_failure}>
            <.pp_alert severity="error">
              Could not load this VM. Try refreshing or signing in again.
            </.pp_alert>
          </:failed>

          <.pp_alert :if={!data.found?} severity="warning">
            VirtualMachine <span class="font-mono">{@namespace}/{@name}</span>
            was not found — it may have been deleted.
          </.pp_alert>

          <div :if={data.found?} class="space-y-6">
            <% {cores, sockets, guest_cpu_total} =
              virtual_machine_cpu_topology_cells(data.vm, data.vmi) %>
            <% cpu_pct = vm_cpu_usage_pct(data.vm, data.vmi, data.usage) %>
            <% mem_pct = vm_mem_usage_pct(data.vm, data.vmi, data.usage) %>
            <div>
              <h1 class="text-2xl font-semibold tracking-tight flex items-center gap-3">
                <.icon name="hero-computer-desktop" class="size-6 text-pp-primary" />
                {vm_meta(data.vm, :name)}
                <span class={vm_phase_badge_classes(data.vm)}>{vm_phase(data.vm)}</span>
                <.pp_chip :if={vmi_agent_connected?(data.vmi)} size="small" color="info">
                  <:icon><.icon name="hero-command-line" class="size-3" /></:icon>
                  Guest agent
                </.pp_chip>
              </h1>
              <p class="text-sm text-base-content/60 mt-1 font-mono">
                {vm_meta(data.vm, :namespace)}
              </p>
            </div>

            <.pp_paper class="p-4">
              <.list>
                <:item title="Boot mode">{vm_boot_mode(data.vm)}</:item>
                <:item title="OS">{vmi_os_display(data.vmi)}</:item>
                <:item title="Cores">{cores}</:item>
                <:item title="Sockets">{sockets}</:item>
                <:item title="CPUs (guest)">{guest_cpu_total}</:item>
                <:item title="Memory">{memory_for_vm_row(data.vm, data.vmi)}</:item>
                <:item title="CPU usage">
                  {vm_cpu_usage_display(data.vm, data.vmi, data.usage)}
                  <span :if={cpu_pct} class={["ml-1", usage_pct_color_class(cpu_pct)]}>
                    {cpu_pct}%
                  </span>
                  <span
                    :if={vm_usage_unavailable?(data.usage)}
                    class="text-base-content/45"
                    title="Usage unavailable — no metrics-server data for this VM's pod yet"
                  >
                    (no metrics)
                  </span>
                </:item>
                <:item title="Memory usage">
                  {vm_mem_usage_display(data.vm, data.vmi, data.usage)}
                  <span :if={mem_pct} class={["ml-1", usage_pct_color_class(mem_pct)]}>
                    {mem_pct}%
                  </span>
                  <span
                    :if={vm_usage_unavailable?(data.usage)}
                    class="text-base-content/45"
                    title="Usage unavailable — no metrics-server data for this VM's pod yet"
                  >
                    (no metrics)
                  </span>
                </:item>
                <:item title="VMI phase">
                  {if(data.vmi, do: vmi_phase(data.vmi), else: "—")}
                </:item>
                <:item title="Ready">
                  {if(data.vmi, do: vmi_ready_label(data.vmi), else: "—")}
                </:item>
                <:item title="Node">
                  {if(data.vmi, do: vmi_scheduling_node_name(data.vmi), else: "—")}
                </:item>
                <:item title="IP">{if(data.vmi, do: vmi_primary_ip(data.vmi), else: "—")}</:item>
                <:item title="Created">{vm_meta(data.vm, :created)}</:item>
              </.list>
            </.pp_paper>

            <% overlay_message =
              "Requires Prometheus scraping cAdvisor container metrics — set PROMETHEUS_URL (see README)"

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
                id={"vm-cpu-usage-chart-#{@namespace}-#{@name}"}
                title={"CPU usage (last 30 min, refreshes every #{format_interval_label(poll_ms())})"}
                height="150px"
                opts={DashboardCharts.usage_area_chart(cpu_points, name: "CPU %")}
                dependency_overlay={overlay}
              />
              <.apex_chart
                id={"vm-mem-usage-chart-#{@namespace}-#{@name}"}
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
                <.icon name="hero-wifi" class="size-5 text-pp-primary" /> Network interfaces
              </h2>
              <.pp_table_container>
                <.pp_table dense>
                  <.pp_table_head>
                    <.pp_table_row>
                      <.pp_table_cell variant="head">Interface</.pp_table_cell>
                      <.pp_table_cell variant="head">Model</.pp_table_cell>
                      <.pp_table_cell variant="head">Binding</.pp_table_cell>
                      <.pp_table_cell variant="head">MAC (spec)</.pp_table_cell>
                      <.pp_table_cell variant="head">MAC (VMI)</.pp_table_cell>
                      <.pp_table_cell variant="head">IP addresses</.pp_table_cell>
                      <.pp_table_cell variant="head">Guest iface</.pp_table_cell>
                    </.pp_table_row>
                  </.pp_table_head>
                  <.pp_table_body>
                    <.pp_table_row :if={data.network_rows == []}>
                      <.pp_table_cell colspan="7" align="center" class="text-pp-on-surface/50 py-6">
                        No network interfaces defined.
                      </.pp_table_cell>
                    </.pp_table_row>
                    <.pp_table_row :for={row <- data.network_rows}>
                      <.pp_table_cell class="text-xs font-mono">{row.iface_name}</.pp_table_cell>
                      <.pp_table_cell class="text-xs">{row.model}</.pp_table_cell>
                      <.pp_table_cell class="text-xs whitespace-nowrap">{row.binding}</.pp_table_cell>
                      <.pp_table_cell class="font-mono text-xs text-pp-on-surface/70">
                        {row.mac_spec}
                      </.pp_table_cell>
                      <.pp_table_cell class="font-mono text-xs text-pp-on-surface/70">
                        {row.mac_live}
                      </.pp_table_cell>
                      <.pp_table_cell class="font-mono text-xs text-pp-on-surface/80">
                        {row.ips}
                      </.pp_table_cell>
                      <.pp_table_cell class="font-mono text-xs text-pp-on-surface/70">
                        {row.guest_iface}
                      </.pp_table_cell>
                    </.pp_table_row>
                  </.pp_table_body>
                </.pp_table>
              </.pp_table_container>
            </div>

            <div class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-circle-stack" class="size-5 text-pp-primary" /> Disks &amp; volumes
              </h2>
              <.pp_table_container>
                <.pp_table dense>
                  <.pp_table_head>
                    <.pp_table_row>
                      <.pp_table_cell variant="head">Disk</.pp_table_cell>
                      <.pp_table_cell variant="head">Device</.pp_table_cell>
                      <.pp_table_cell variant="head">Bus</.pp_table_cell>
                      <.pp_table_cell variant="head">Boot</.pp_table_cell>
                      <.pp_table_cell variant="head">Volume kind</.pp_table_cell>
                      <.pp_table_cell variant="head">Source</.pp_table_cell>
                      <.pp_table_cell variant="head">Size</.pp_table_cell>
                      <.pp_table_cell variant="head">Storage class</.pp_table_cell>
                      <.pp_table_cell variant="head">PVC phase</.pp_table_cell>
                    </.pp_table_row>
                  </.pp_table_head>
                  <.pp_table_body>
                    <.pp_table_row :if={data.disk_rows == []}>
                      <.pp_table_cell colspan="9" align="center" class="text-pp-on-surface/50 py-6">
                        No disks defined.
                      </.pp_table_cell>
                    </.pp_table_row>
                    <.pp_table_row :for={row <- data.disk_rows}>
                      <.pp_table_cell class="text-xs font-mono">{row.disk_name}</.pp_table_cell>
                      <.pp_table_cell class="text-xs">{row.device_kind}</.pp_table_cell>
                      <.pp_table_cell class="text-xs font-mono">{row.bus}</.pp_table_cell>
                      <.pp_table_cell class="text-xs tabular-nums">{row.boot_order}</.pp_table_cell>
                      <.pp_table_cell class="text-xs whitespace-nowrap">
                        {row.volume_kind}
                      </.pp_table_cell>
                      <.pp_table_cell class="text-xs font-mono text-pp-on-surface/75">
                        {row.source}
                      </.pp_table_cell>
                      <.pp_table_cell class="text-xs tabular-nums whitespace-nowrap">
                        {row.size}
                      </.pp_table_cell>
                      <.pp_table_cell class="text-xs">{row.storage_class}</.pp_table_cell>
                      <.pp_table_cell class="text-xs">{row.pvc_phase}</.pp_table_cell>
                    </.pp_table_row>
                  </.pp_table_body>
                </.pp_table>
              </.pp_table_container>
            </div>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
