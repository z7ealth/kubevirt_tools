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
          class="text-sm text-pp-primary hover:underline"
        >
          &larr; Back to Storage classes
        </.link>

        <.async_result :let={data} assign={@sc_detail}>
          <:loading>
            <.pp_paper
              elevation={0}
              class="flex items-center gap-3 border border-pp-outline/20 bg-pp-surface-variant/40 px-5 py-12 text-pp-on-surface/70"
            >
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading storage class…</span>
            </.pp_paper>
          </:loading>
          <:failed :let={_failure}>
            <.pp_alert severity="error">
              Could not load this storage class. Try refreshing or signing in again.
            </.pp_alert>
          </:failed>

          <.pp_alert :if={!data.found?} severity="warning">
            StorageClass <span class="font-mono">{@name}</span>
            was not found — it may have been deleted.
          </.pp_alert>

          <div :if={data.found?} class="space-y-6">
            <div>
              <h1 class="text-2xl font-semibold tracking-tight flex items-center gap-3">
                <.icon name="hero-archive-box" class="size-6 text-pp-primary" /> {data.row.name}
                <.pp_chip :if={data.row.default?} size="small" color="primary">default</.pp_chip>
              </h1>
            </div>

            <.pp_paper class="p-4">
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
            </.pp_paper>

            <div class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-circle-stack" class="size-5 text-pp-primary" />
                PVCs using this class
              </h2>
              <.pp_table_container>
                <.pp_table dense>
                  <.pp_table_head>
                    <.pp_table_row>
                      <.pp_table_cell variant="head">Namespace</.pp_table_cell>
                      <.pp_table_cell variant="head">Name</.pp_table_cell>
                      <.pp_table_cell variant="head">Phase</.pp_table_cell>
                      <.pp_table_cell variant="head">Capacity</.pp_table_cell>
                    </.pp_table_row>
                  </.pp_table_head>
                  <.pp_table_body>
                    <.pp_table_row :if={data.pvcs == []}>
                      <.pp_table_cell colspan="4" align="center" class="text-pp-on-surface/50 py-6">
                        No PVCs use this storage class.
                      </.pp_table_cell>
                    </.pp_table_row>
                    <.pp_table_row :for={pvc <- data.pvcs}>
                      <.pp_table_cell class="font-mono text-xs">
                        {vm_meta(pvc, :namespace)}
                      </.pp_table_cell>
                      <.pp_table_cell class="font-mono text-xs font-medium">
                        {vm_meta(pvc, :name)}
                      </.pp_table_cell>
                      <.pp_table_cell class="text-xs">
                        {get_in(pvc, ["status", "phase"]) || "—"}
                      </.pp_table_cell>
                      <.pp_table_cell class="text-xs font-mono">
                        {get_in(pvc, ["status", "capacity", "storage"]) || "—"}
                      </.pp_table_cell>
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
