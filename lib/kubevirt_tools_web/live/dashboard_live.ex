defmodule KubevirtToolsWeb.DashboardLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  alias KubevirtTools.KubeVirt
  alias KubevirtTools.KubeconfigStore

  @impl true
  def mount(_params, _session, socket) do
    token = socket.assigns.kubeconfig_token

    {:ok,
     socket
     |> assign(:page_title, "KubeVirt")
     |> assign(:current_scope, %{label: "Cluster session"})
     |> assign_async(:kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    token = socket.assigns.kubeconfig_token

    {:noreply,
     socket
     |> assign_async(:kubevirt, fn -> load_kubevirt(token) end)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="space-y-8">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight">KubeVirt dashboard</h1>
            <p class="mt-1 text-sm text-base-content/65">
              VirtualMachines and VirtualMachineInstances from your connected cluster.
            </p>
          </div>
          <button
            type="button"
            phx-click="refresh"
            id="dashboard-refresh"
            class="btn btn-outline btn-sm gap-2 self-start sm:self-auto transition hover:border-primary/60"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Refresh
          </button>
        </div>

        <.async_result :let={data} assign={@kubevirt}>
          <:loading>
            <div class="flex items-center gap-3 rounded-xl border border-base-300/70 bg-base-200/40 px-5 py-8 text-base-content/70">
              <.icon name="hero-arrow-path" class="size-6 motion-safe:animate-spin" />
              <span>Loading KubeVirt resources…</span>
            </div>
          </:loading>
          <:failed :let={_failure}>
            <div class="alert alert-error">
              <.icon name="hero-exclamation-circle" class="size-5 shrink-0" />
              <span>Could not load KubeVirt data. Try refreshing or signing in again.</span>
            </div>
          </:failed>

          <div class="space-y-10" id="kubevirt-dashboard-content">
            <div class="flex flex-wrap gap-2 text-xs text-base-content/60">
              <span :if={data.cluster} class="badge badge-ghost badge-sm gap-1">
                <.icon name="hero-cube" class="size-3.5" /> Cluster: {data.cluster}
              </span>
              <span :if={data.user} class="badge badge-ghost badge-sm gap-1">
                <.icon name="hero-user" class="size-3.5" /> User: {data.user}
              </span>
            </div>

            <section class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-computer-desktop" class="size-5 text-primary" /> VirtualMachines
              </h2>
              <%= if data.vm_error do %>
                <div class="alert alert-warning text-sm">
                  <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                  <span>
                    Could not list VirtualMachines — KubeVirt may be missing or RBAC may deny access ({vm_error_text(
                      data.vm_error
                    )}).
                  </span>
                </div>
              <% else %>
                <.vm_table items={data.vms} empty_label="No VirtualMachines found." id_prefix="vm" />
              <% end %>
            </section>

            <section class="space-y-3">
              <h2 class="text-lg font-medium flex items-center gap-2">
                <.icon name="hero-cpu-chip" class="size-5 text-secondary" /> VirtualMachineInstances
              </h2>
              <%= if data.vmi_error do %>
                <div class="alert alert-warning text-sm">
                  <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
                  <span>Could not list VMIs ({vm_error_text(data.vmi_error)}).</span>
                </div>
              <% else %>
                <.vmi_table items={data.vmis} empty_label="No VMIs found." id_prefix="vmi" />
              <% end %>
            </section>
          </div>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end

  attr :items, :list, required: true
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp vm_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>Phase</th>
            <th>Created</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@items == []}>
            <td colspan="4" class="text-center text-base-content/50 py-8">{@empty_label}</td>
          </tr>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs">{vm_meta(item, :namespace)}</td>
              <td class="font-medium">{vm_meta(item, :name)}</td>
              <td>
                <span class="badge badge-sm badge-outline">{vm_phase(item)}</span>
              </td>
              <td class="text-xs text-base-content/60">{vm_meta(item, :created)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  attr :items, :list, required: true
  attr :empty_label, :string, required: true
  attr :id_prefix, :string, required: true

  defp vmi_table(assigns) do
    ~H"""
    <div class="overflow-x-auto rounded-xl border border-base-300/70 bg-base-100 shadow-sm">
      <table class="table table-sm">
        <thead class="bg-base-200/60 text-base-content/80">
          <tr>
            <th>Namespace</th>
            <th>Name</th>
            <th>Phase</th>
            <th>Node</th>
          </tr>
        </thead>
        <tbody>
          <tr :if={@items == []}>
            <td colspan="4" class="text-center text-base-content/50 py-8">{@empty_label}</td>
          </tr>
          <%= for {item, i} <- Enum.with_index(@items) do %>
            <tr id={"#{@id_prefix}-row-#{i}"} class="hover:bg-base-200/40 transition-colors">
              <td class="font-mono text-xs">{vm_meta(item, :namespace)}</td>
              <td class="font-medium">{vm_meta(item, :name)}</td>
              <td>
                <span class="badge badge-sm badge-outline">{vmi_phase(item)}</span>
              </td>
              <td class="font-mono text-xs text-base-content/70">{vmi_node(item)}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp load_kubevirt(token) do
    with {:ok, yaml} <- KubeconfigStore.get(token),
         {:ok, conn} <- K8s.Conn.from_string(yaml) do
      {vms, vm_err} = safe_list(&KubeVirt.list_virtual_machines/1, conn)
      {vmis, vmi_err} = safe_list(&KubeVirt.list_virtual_machine_instances/1, conn)

      {:ok,
       %{
         kubevirt: %{
           cluster: conn.cluster_name,
           user: conn.user_name,
           vms: vms,
           vmis: vmis,
           vm_error: vm_err,
           vmi_error: vmi_err
         }
       }}
    else
      :error ->
        {:error, :invalid_session}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_list(fun, conn) do
    case fun.(conn) do
      {:ok, items} -> {items, nil}
      {:error, reason} -> {[], reason}
    end
  end

  defp vm_error_text(%K8s.Client.HTTPError{message: m}) when is_binary(m), do: m
  defp vm_error_text(%{message: m}) when is_binary(m), do: m
  defp vm_error_text(other), do: inspect(other)

  defp vm_meta(item, :namespace), do: get_in(item, ["metadata", "namespace"]) || "—"
  defp vm_meta(item, :name), do: get_in(item, ["metadata", "name"]) || "—"

  defp vm_meta(item, :created) do
    case get_in(item, ["metadata", "creationTimestamp"]) do
      nil -> "—"
      ts -> ts
    end
  end

  defp vm_phase(item) do
    get_in(item, ["status", "printableStatus"]) || "—"
  end

  defp vmi_phase(item) do
    get_in(item, ["status", "phase"]) || "—"
  end

  defp vmi_node(item) do
    get_in(item, ["status", "nodeName"]) || "—"
  end
end
