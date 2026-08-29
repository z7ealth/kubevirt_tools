defmodule KubevirtToolsWeb.TabComponents do
  @moduledoc """
  LiveView-driven tabs styled to match `PhoenixPaper.Tab`.

  Switching stays server-side (the dashboard needs `?tab=` deep links and
  per-tab lazy content, which PhoenixPaper's client-only `pp_tabs` can't
  express) — only the trigger styling comes from PhoenixPaper. Pass a list of
  tab definitions and the current `active` id; tab switches use `phx-click`
  (default event `"set_tab"`) with `phx-value-tab` set to each tab's string id.

  ## Example

      <.daisy_tabs id="main-tabs" active={@active_tab} event="set_tab" tabs={tab_defs()} />
      <.tab_panel root_id="main-tabs" tab={:home} active={@active_tab}>…</.tab_panel>
  """
  use Phoenix.Component

  @doc """
  Tab triggers styled like `PhoenixPaper.Tab` (an underline indicator on the
  selected tab).

  `tabs` is a list of maps: `%{id: atom | String.t(), label: String.t(), optional :disabled => boolean}`.

  `variant` is accepted for backwards compatibility but no longer changes the
  look. `active_style`: `:default` (underline indicator) or `:outline_primary`
  (a rounded pill group).
  """
  attr :id, :string, required: true, doc: "Stable id prefix for tab buttons and panels"
  attr :active, :atom, required: true, doc: "Currently selected tab id (atom)"
  attr :tabs, :list, required: true, doc: "List of tab definition maps"
  attr :event, :string, default: "set_tab", doc: "LiveView event name for enabled tabs"
  attr :variant, :atom, default: :box, values: [:box, :lift, :border]
  attr :active_style, :atom, default: :default, values: [:default, :outline_primary]
  attr :class, :any, default: nil

  def daisy_tabs(assigns) do
    assigns = assign(assigns, :outline_primary?, assigns.active_style == :outline_primary)

    ~H"""
    <div
      role="tablist"
      class={
        if @outline_primary? do
          ["flex flex-wrap items-center gap-1.5 sm:gap-2", @class]
        else
          ["flex w-full flex-wrap sm:flex-nowrap border-b border-pp-outline/20", @class]
        end
      }
      id={@id}
    >
      <%= for t <- @tabs do %>
        <% disabled = Map.get(t, :disabled, false) %>
        <% tid = tab_id_string(t.id) %>
        <% active = @active == t.id %>
        <button
          type="button"
          role="tab"
          id={"#{@id}-tab-#{tid}"}
          aria-selected={active}
          aria-controls={"#{@id}-panel-#{tid}"}
          phx-click={unless disabled, do: @event}
          phx-value-tab={tid}
          disabled={disabled}
          data-pp-component="tab"
          class={tab_trigger_classes(active, disabled, @outline_primary?)}
        >
          {t.label}
        </button>
      <% end %>
    </div>
    """
  end

  @pill_base "inline-flex items-center gap-1.5 shrink-0 whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-medium transition-colors"
  @tab_base "inline-flex items-center justify-center gap-2 shrink-0 whitespace-nowrap border-b-2 px-4 py-3 text-sm font-medium cursor-pointer select-none transition-colors"

  defp tab_trigger_classes(_active, true, true),
    do: [@pill_base, "opacity-40 cursor-not-allowed text-pp-on-surface/50"]

  defp tab_trigger_classes(true, false, true),
    do: [@pill_base, "border border-pp-primary bg-pp-primary/10 text-pp-primary"]

  defp tab_trigger_classes(false, false, true),
    do: [@pill_base, "text-pp-on-surface/65 hover:text-pp-on-surface hover:bg-pp-on-surface/5"]

  defp tab_trigger_classes(true, false, false),
    do: [@tab_base, "border-pp-primary text-pp-primary"]

  defp tab_trigger_classes(false, false, false),
    do: [
      @tab_base,
      "border-transparent text-pp-on-surface/70 hover:text-pp-on-surface hover:bg-pp-on-surface/5"
    ]

  defp tab_trigger_classes(_active, true, false),
    do: [@tab_base, "border-transparent text-pp-on-surface/40 opacity-40 cursor-not-allowed"]

  @doc """
  One tabpanel; show with `active == tab`. Links `aria-labelledby` to the matching `daisy_tabs` button.
  """
  attr :root_id, :string, required: true
  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def tab_panel(assigns) do
    tid = Atom.to_string(assigns.tab)
    hidden = assigns.active != assigns.tab
    assigns = assigns |> assign(:tid, tid) |> assign(:hidden?, hidden)

    ~H"""
    <div
      role="tabpanel"
      id={"#{@root_id}-panel-#{@tid}"}
      aria-labelledby={"#{@root_id}-tab-#{@tid}"}
      hidden={@hidden?}
      class={["outline-none", @hidden? && "hidden", @class]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp tab_id_string(id) when is_atom(id), do: Atom.to_string(id)
  defp tab_id_string(id) when is_binary(id), do: id
end
