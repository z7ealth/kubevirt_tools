defmodule KubevirtToolsWeb.StorageClassShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterExportLists
  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "StorageClass: #{name}")
      |> assign(:name, name)

    {:ok, assign_async(socket, :sc_detail, fn -> load_sc_detail(token, name) end)}
  end

  defp load_sc_detail(token, name) do
    with {:ok, conn} <- K8sConn.from_token(token),
         {:ok, storage_classes} <- ClusterExportLists.list_storage_classes(conn),
         {:ok, pvcs} <- ClusterInventory.list_pvcs(conn) do
      case Enum.find(storage_classes, &(get_in(&1, ["metadata", "name"]) == name)) do
        nil ->
          {:ok, %{sc_detail: %{found?: false}}}

        sc ->
          pvc_by_class = pvc_counts_by_storage_class_name(pvcs)
          [row] = storage_classes_table_rows([sc], pvc_by_class)

          matching_pvcs =
            pvcs
            |> Enum.filter(&(get_in(&1, ["spec", "storageClassName"]) == name))
            |> Enum.sort_by(&{vm_meta(&1, :namespace), vm_meta(&1, :name)})

          {:ok, %{sc_detail: %{found?: true, row: row, pvcs: matching_pvcs}}}
      end
    else
      :error -> {:error, :invalid_session}
      {:error, reason} -> {:error, K8sSafeError.user_facing(reason)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-full min-w-0">
        <.link
          navigate={~p"/dashboard?tab=storage_classes"}
          class="link link-hover text-sm text-base-content/60"
        >
          &larr; Back to Storage classes
        </.link>

        <.async_result :let={data} assign={@sc_detail}>
          <:loading>
            <div class="flex items-center gap-3 rounded-xl border border-base-300/70 bg-base-200/40 px-5 py-12 text-base-content/70">
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading storage class…</span>
            </div>
          </:loading>
          <:failed :let={_failure}>
            <div class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
              <span>Could not load this storage class. Try refreshing or signing in again.</span>
            </div>
          </:failed>

          <div :if={!data.found?} class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
            <span>
              StorageClass <span class="font-mono">{@name}</span>
              was not found — it may have been deleted.
            </span>
          </div>

          <div :if={data.found?} class="space-y-6">
            <div>
              <h1 class="text-2xl font-semibold tracking-tight flex items-center gap-3">
                <.icon name="hero-archive-box" class="size-6 text-primary" /> {data.row.name}
                <span :if={data.row.default?} class="badge badge-sm badge-primary">default</span>
              </h1>
            </div>

            <div class="rounded-xl border border-base-300/70 bg-base-100 shadow-sm p-4">
              <.list>
                <:item title="Provisioner">{data.row.provisioner}</:item>
                <:item title="Reclaim policy">{data.row.reclaim}</:item>
                <:item title="Volume binding">{data.row.binding}</:item>
                <:item title="Allows expansion">
                  {cond do
                    data.row.expand == true -> "Yes"
                    data.row.expand == false -> "No"
                    true -> "—"
                  end}
                </:item>
                <:item title="PVCs using this class">{data.row.pvc_count}</:item>
                <:item title="Parameters">{data.row.parameters_full}</:item>
              </.list>
            </div>

            <div class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-circle-stack" class="size-5 text-primary" /> PVCs using this class
              </h2>
              <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
                <table class="table table-sm">
                  <thead class="bg-base-200/60 text-base-content/80">
                    <tr>
                      <th>Namespace</th>
                      <th>Name</th>
                      <th>Phase</th>
                      <th>Capacity</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :if={data.pvcs == []}>
                      <td colspan="4" class="text-center text-base-content/50 py-6">
                        No PVCs use this storage class.
                      </td>
                    </tr>
                    <tr :for={pvc <- data.pvcs} class="hover:bg-base-200/40">
                      <td class="font-mono text-xs">{vm_meta(pvc, :namespace)}</td>
                      <td class="font-mono text-xs font-medium">{vm_meta(pvc, :name)}</td>
                      <td class="text-xs">{get_in(pvc, ["status", "phase"]) || "—"}</td>
                      <td class="text-xs font-mono">
                        {get_in(pvc, ["status", "capacity", "storage"]) || "—"}
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
