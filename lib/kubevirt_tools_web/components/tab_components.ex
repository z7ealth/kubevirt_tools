defmodule KubevirtToolsWeb.TabComponents do
  @moduledoc """
  LiveView-driven MD3 primary tabs.

  Switching stays server-side (the dashboard needs `?tab=` deep links and
  per-tab state), which PhoenixPaper's client-only `pp_tabs` can't express:
  its tabs always run their own `Tabs.select/2` on click. So the triggers are
  rendered here, built from the same MD3 parts `PhoenixPaper.Tab` uses —
  `title-small` labels, the state layer, the focus ring, the ripple and the
  3dp primary indicator under the label — with selection driven by the
  `active` assign. Tab switches use `phx-click` (default event `"set_tab"`)
  with `phx-value-tab` set to each tab's string id.

  ## Example

      <.live_tabs id="main-tabs" active={@active_tab} event="set_tab" tabs={tab_defs()} />
      <.tab_panel root_id="main-tabs" tab={:home} active={@active_tab}>…</.tab_panel>
  """
  use Phoenix.Component

  alias PhoenixPaper.Ripple

  @doc """
  MD3 primary tabs (scrollable layout).

  `tabs` is a list of maps:
  `%{id: atom | String.t(), label: String.t(), optional :icon => String.t(), optional :disabled => boolean}`.
  """
  attr :id, :string, required: true, doc: "Stable id prefix for tab buttons and panels"
  attr :active, :atom, required: true, doc: "Currently selected tab id (atom)"
  attr :tabs, :list, required: true, doc: "List of tab definition maps"
  attr :event, :string, default: "set_tab", doc: "LiveView event name for enabled tabs"
  attr :class, :any, default: nil

  def live_tabs(assigns) do
    ~H"""
    <div
      role="tablist"
      id={@id}
      class={[
        "flex items-stretch overflow-x-auto [scrollbar-width:none]",
        @class
      ]}
    >
      <%= for t <- @tabs do %>
        <% disabled = Map.get(t, :disabled, false) %>
        <% tid = tab_id_string(t.id) %>
        <% active = @active == t.id %>
        <button
          type="button"
          role="tab"
          id={"#{@id}-tab-#{tid}"}
          aria-selected={to_string(active)}
          aria-controls={"#{@id}-panel-#{tid}"}
          phx-click={unless disabled, do: @event}
          phx-value-tab={tid}
          disabled={disabled}
          onclick={Ripple.on_click(!disabled)}
          class={[
            "relative inline-flex h-12 min-w-[90px] shrink-0 cursor-pointer select-none items-stretch justify-center overflow-hidden px-4",
            "pp-title-small pp-state-layer pp-focus-ring pp-motion-effects-fast",
            "text-pp-on-surface-variant hover:text-pp-on-surface aria-selected:text-pp-primary",
            "disabled:pointer-events-none disabled:text-pp-on-surface/38"
          ]}
        >
          <span class="relative inline-flex items-center justify-center gap-2 whitespace-nowrap">
            <span :if={t[:icon]} class={[t[:icon], "size-[18px]"]} />
            {t.label}
            <span class={[
              "absolute inset-x-0.5 bottom-0 h-[3px] min-w-6 rounded-t-[3px] bg-pp-primary",
              "pp-motion-effects-fast",
              if(active, do: "opacity-100", else: "opacity-0")
            ]} />
          </span>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  One tabpanel; shown when `active == tab`. Links `aria-labelledby` to the
  matching `live_tabs` button.
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
