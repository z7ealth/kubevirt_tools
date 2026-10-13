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
        <.pp_breadcrumbs id="network-breadcrumbs">
          <:item navigate={~p"/dashboard"}>Dashboard</:item>
          <:item navigate={~p"/dashboard?tab=networks"}>Networks</:item>
          <:item>{@iface_name}</:item>
        </.pp_breadcrumbs>

        <.async_result :let={data} assign={@row_detail}>
          <:loading>
            <.loading_card label="Loading interface…" />
          </:loading>
          <:failed :let={_failure}>
            <.banner kind={:error}>
              Could not load this interface. Try refreshing or signing in again.
            </.banner>
          </:failed>

          <.banner :if={!data.found?} kind={:warning}>
            Interface <span class="font-mono">{@iface_name}</span>
            on <span class="font-mono">{@namespace}/{@vm_name}</span>
            was not found — the VM or its interface may have changed.
          </.banner>

          <div :if={data.found?} class="space-y-6">
            <.page_title icon="hero-wifi">
              {data.row.iface_name}
              <:chips>
                <.status_chip tone={phase_tone(data.row.vmi_phase)}>
                  {data.row.vmi_phase}
                </.status_chip>
              </:chips>
              <:subtitle>
                on
                <.link
                  navigate={~p"/vms/#{@namespace}/#{@vm_name}"}
                  class="text-pp-primary hover:underline font-mono"
                >
                  {@namespace}/{@vm_name}
                </.link>
              </:subtitle>
            </.page_title>

            <.list id="network-details">
              <:item title="Model">{data.row.model}</:item>
              <:item title="Binding">{data.row.binding}</:item>
              <:item title="MAC (spec)">{data.row.mac_spec}</:item>
              <:item title="MAC (VMI)">{data.row.mac_live}</:item>
              <:item title="IP addresses">{data.row.ips}</:item>
              <:item title="Guest interface">{data.row.guest_iface}</:item>
              <:item title="VMI phase">{data.row.vmi_phase}</:item>
            </.list>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
