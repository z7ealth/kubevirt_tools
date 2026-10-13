defmodule KubevirtToolsWeb.DiskShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
  alias KubevirtTools.KubeVirt

  @impl true
  def mount(
        %{"namespace" => ns, "vm_name" => vm_name, "disk_name" => disk_name},
        _session,
        socket
      ) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "Disk: #{disk_name}")
      |> assign(:namespace, ns)
      |> assign(:vm_name, vm_name)
      |> assign(:disk_name, disk_name)

    {:ok, assign_async(socket, :row_detail, fn -> load_row(token, ns, vm_name, disk_name) end)}
  end

  defp load_row(token, ns, vm_name, disk_name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, vms} <- KubeVirt.list_virtual_machines(conn),
         {:ok, pvcs} <- ClusterInventory.list_pvcs(conn) do
      case Enum.find(vms, &matches?(&1, ns, vm_name)) do
        nil ->
          {:ok, %{row_detail: %{found?: false}}}

        vm ->
          rows = virtual_machine_disk_detail_rows([vm], pvcs)

          case Enum.find(rows, &(&1.disk_name == disk_name)) do
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
        <.pp_breadcrumbs id="disk-breadcrumbs">
          <:item navigate={~p"/dashboard"}>Dashboard</:item>
          <:item navigate={~p"/dashboard?tab=disks"}>Disks</:item>
          <:item>{@disk_name}</:item>
        </.pp_breadcrumbs>

        <.async_result :let={data} assign={@row_detail}>
          <:loading>
            <.loading_card label="Loading disk…" />
          </:loading>
          <:failed :let={_failure}>
            <.banner kind={:error}>
              Could not load this disk. Try refreshing or signing in again.
            </.banner>
          </:failed>

          <.banner :if={!data.found?} kind={:warning}>
            Disk <span class="font-mono">{@disk_name}</span>
            on <span class="font-mono">{@namespace}/{@vm_name}</span>
            was not found — the VM or its disks may have changed.
          </.banner>

          <div :if={data.found?} class="space-y-6">
            <.page_title icon="hero-circle-stack">
              {data.row.disk_name}
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

            <.list id="disk-details">
              <:item title="Device">{data.row.device_kind}</:item>
              <:item title="Bus">{data.row.bus}</:item>
              <:item title="Boot order">{data.row.boot_order}</:item>
              <:item title="Removable">{if(data.row.removable?, do: "Yes", else: "No")}</:item>
              <:item title="Volume kind">{data.row.volume_kind}</:item>
              <:item title="Source">{data.row.source}</:item>
              <:item title="Size">{data.row.size}</:item>
              <:item title="Storage class">{data.row.storage_class}</:item>
              <:item title="PVC phase">{data.row.pvc_phase}</:item>
              <:item title="Serial">{data.row.serial}</:item>
              <:item title="Cache">{data.row.cache}</:item>
            </.list>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
