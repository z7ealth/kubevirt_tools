defmodule KubevirtToolsWeb.NetworkShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
  alias KubevirtTools.KubeVirt

  @impl true
  def mount(
        %{"namespace" => ns, "vm_name" => vm_name, "iface_name" => iface_name},
        _session,
        socket
      ) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Interface: #{iface_name}")
      |> assign(:namespace, ns)
      |> assign(:vm_name, vm_name)
      |> assign(:iface_name, iface_name)

    {:ok, assign_async(socket, :row_detail, fn -> load_row(token, ns, vm_name, iface_name) end)}
  end

  defp load_row(token, ns, vm_name, iface_name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, vms} <- KubeVirt.list_virtual_machines(conn),
         {:ok, vmis} <- KubeVirt.list_virtual_machine_instances(conn) do
      case Enum.find(vms, &matches?(&1, ns, vm_name)) do
        nil ->
          {:ok, %{row_detail: %{found?: false}}}

        vm ->
          vmi = Enum.find(vmis, &matches?(&1, ns, vm_name))
          rows = virtual_machine_network_interface_rows([vm], List.wrap(vmi))

          case Enum.find(rows, &(&1.iface_name == iface_name)) do
            nil -> {:ok, %{row_detail: %{found?: false}}}
            row -> {:ok, %{row_detail: %{found?: true, row: row}}}
          end
      end
    else
      :error -> {:error, :invalid_session}
      {:error, reason} -> {:error, K8sSafeError.user_facing(reason)}
    end
  end

  defp matches?(item, ns, name),
    do: vm_meta(item, :namespace) == ns and vm_meta(item, :name) == name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-full min-w-0">
        <.link
          navigate={~p"/dashboard?tab=networks"}
          class="text-sm text-pp-primary hover:underline"
        >
          &larr; Back to Networks
        </.link>

        <.async_result :let={data} assign={@row_detail}>
          <:loading>
            <.pp_paper
              elevation={0}
              class="flex items-center gap-3 border border-pp-outline/20 bg-pp-surface-variant/40 px-5 py-12 text-pp-on-surface/70"
            >
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading interface…</span>
            </.pp_paper>
          </:loading>
          <:failed :let={_failure}>
            <.pp_alert severity="error">
              Could not load this interface. Try refreshing or signing in again.
            </.pp_alert>
          </:failed>

          <.pp_alert :if={!data.found?} severity="warning">
            Interface <span class="font-mono">{@iface_name}</span>
            on <span class="font-mono">{@namespace}/{@vm_name}</span>
            was not found — the VM or its interface may have changed.
          </.pp_alert>

          <div :if={data.found?} class="space-y-6">
            <div>
              <h1 class="text-2xl font-semibold tracking-tight flex items-center gap-3">
                <.icon name="hero-wifi" class="size-6 text-pp-primary" /> {data.row.iface_name}
              </h1>
              <p class="text-sm text-base-content/60 mt-1">
                on
                <.link
                  navigate={~p"/vms/#{@namespace}/#{@vm_name}"}
                  class="text-pp-primary hover:underline font-mono"
                >
                  {@namespace}/{@vm_name}
                </.link>
              </p>
            </div>

            <.pp_paper class="p-4">
              <.list>
                <:item title="Model">{data.row.model}</:item>
                <:item title="Binding">{data.row.binding}</:item>
                <:item title="MAC (spec)">{data.row.mac_spec}</:item>
                <:item title="MAC (VMI)">{data.row.mac_live}</:item>
                <:item title="IP addresses">{data.row.ips}</:item>
                <:item title="Guest interface">{data.row.guest_iface}</:item>
                <:item title="VMI phase">{data.row.vmi_phase}</:item>
              </.list>
            </.pp_paper>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
