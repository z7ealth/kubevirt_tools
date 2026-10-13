defmodule KubevirtToolsWeb.StorageClassShowLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  import KubevirtTools.VmPresentation

  alias KubevirtTools.ClusterExportLists
  alias KubevirtTools.ClusterInventory
  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError
  alias KubevirtToolsWeb.PaginationComponents

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    token = socket.assigns.kubeconfig_token

    socket =
      socket
      |> assign(:page_title, "StorageClass: #{name}")
      |> assign(:name, name)
      |> assign(:pagination, PaginationComponents.new(["pvcs"]))

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
  def handle_event(event, params, socket) when event in ["set_page", "set_per_page"] do
    {:noreply,
     update(socket, :pagination, &PaginationComponents.handle_pagination_event(&1, event, params))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <div class="space-y-6 max-w-full min-w-0">
        <.pp_breadcrumbs id="storage-class-breadcrumbs">
          <:item navigate={~p"/dashboard"}>Dashboard</:item>
          <:item navigate={~p"/dashboard?tab=storage_classes"}>Storage classes</:item>
          <:item>{@name}</:item>
        </.pp_breadcrumbs>

        <.async_result :let={data} assign={@sc_detail}>
          <:loading>
            <.loading_card label="Loading storage class…" />
          </:loading>
          <:failed :let={_failure}>
            <.banner kind={:error}>
              Could not load this storage class. Try refreshing or signing in again.
            </.banner>
          </:failed>

          <.banner :if={!data.found?} kind={:warning}>
            StorageClass <span class="font-mono">{@name}</span>
            was not found — it may have been deleted.
          </.banner>

          <div :if={data.found?} class="space-y-6">
            <.page_title icon="hero-archive-box">
              {data.row.name}
              <:chips>
                <.status_chip :if={data.row.default?} icon="hero-star-mini" selected>
                  default
                </.status_chip>
              </:chips>
            </.page_title>

            <.list id="storage-class-details">
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

            <div class="space-y-3">
              <.section_title icon="hero-circle-stack">PVCs using this class</.section_title>
              <.pp_table_container class="!overflow-visible">
                <div class="overflow-x-auto rounded-t-pp-md">
                  <.pp_table>
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
                        <.pp_table_cell
                          colspan="4"
                          align="center"
                          class="py-8 text-pp-on-surface-variant"
                        >
                          No PVCs use this storage class.
                        </.pp_table_cell>
                      </.pp_table_row>
                      <.pp_table_row :for={pvc <- paginate(data.pvcs, @pagination["pvcs"]).rows}>
                        <.pp_table_cell class="font-mono text-pp-on-surface-variant">
                          {vm_meta(pvc, :namespace)}
                        </.pp_table_cell>
                        <.pp_table_cell class="font-mono font-medium">
                          {vm_meta(pvc, :name)}
                        </.pp_table_cell>
                        <.pp_table_cell>
                          <% pvc_phase = get_in(pvc, ["status", "phase"]) || "—" %>
                          <.status_chip tone={pvc_phase_tone(pvc_phase)}>{pvc_phase}</.status_chip>
                        </.pp_table_cell>
                        <.pp_table_cell class="font-mono tabular-nums">
                          {get_in(pvc, ["status", "capacity", "storage"]) || "—"}
                        </.pp_table_cell>
                      </.pp_table_row>
                    </.pp_table_body>
                  </.pp_table>
                </div>
                <.table_pager
                  id="pvcs-pagination"
                  key="pvcs"
                  page={paginate(data.pvcs, @pagination["pvcs"])}
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
