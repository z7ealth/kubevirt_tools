defmodule KubevirtToolsWeb.TabComponents do
  @moduledoc """
  [DaisyUI tabs](https://daisyui.com/components/tab/) driven by LiveView.

  Pass a list of tab definitions and the current `active` id; tab switches use `phx-click`
  (default event `"set_tab"`) with `phx-value-tab` set to each tab's string id.

  ## Example

      <.daisy_tabs id="main-tabs" active={@active_tab} event="set_tab" tabs={tab_defs()} />
      <.tab_panel root_id="main-tabs" tab={:home} active={@active_tab}>…</.tab_panel>
  """
  use Phoenix.Component

  @doc """
  Tab triggers using DaisyUI `tabs` + `tabs-box` (boxed pill group).

  `tabs` is a list of maps: `%{id: atom | String.t(), label: String.t(), optional: :disabled => boolean}`.

  Optional `variant`: `:box` (default), `:lift`, `:border` — maps to DaisyUI `tabs-box`, `tabs-lift`, `tabs-border`.

  Optional `active_style`: `:default` (Daisy `tab-active` fill) or `:outline_primary` (`btn-outline btn-primary` on active).
  """
  attr :id, :string, required: true, doc: "Stable id prefix for tab buttons and panels"
  attr :active, :atom, required: true, doc: "Currently selected tab id (atom)"
  attr :tabs, :list, required: true, doc: "List of tab definition maps"
  attr :event, :string, default: "set_tab", doc: "LiveView event name for enabled tabs"
  attr :variant, :atom, default: :box, values: [:box, :lift, :border]
  attr :active_style, :atom, default: :default, values: [:default, :outline_primary]
  attr :class, :any, default: nil

  def daisy_tabs(assigns) do
    outline? = assigns.active_style == :outline_primary

    variant_class =
      if outline? do
        nil
      else
        case assigns.variant do
          :box -> "tabs-box"
          :lift -> "tabs-lift"
          :border -> "tabs-border"
        end
      end

    assigns =
      assigns
      |> assign(:outline_primary?, outline?)
      |> assign(:variant_class, variant_class)

    ~H"""
    <div
      role="tablist"
      class={
        if @outline_primary? do
          ["flex flex-wrap items-center gap-1.5 sm:gap-2", @class]
        else
          ["tabs", @variant_class, "w-full", "flex-wrap", "sm:flex-nowrap", "gap-0.5", @class]
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
          class={tab_trigger_classes(active, disabled, @outline_primary?)}
        >
          {t.label}
        </button>
      <% end %>
    </div>
    """
  end

  defp tab_trigger_classes(_active, true, true),
    do: [
      "btn btn-sm shrink-0 whitespace-nowrap btn-ghost btn-disabled opacity-40 cursor-not-allowed"
    ]

  defp tab_trigger_classes(true, false, true),
    do: ["btn btn-sm shrink-0 whitespace-nowrap btn-outline btn-primary"]

  defp tab_trigger_classes(false, false, true),
    do: [
      "btn btn-sm shrink-0 whitespace-nowrap btn-ghost",
      "text-base-content/65 hover:text-base-content",
      "hover:bg-base-200/60 transition-colors"
    ]

  defp tab_trigger_classes(true, false, false),
    do: ["tab shrink-0 whitespace-nowrap tab-active"]

  defp tab_trigger_classes(false, false, false),
    do: ["tab shrink-0 whitespace-nowrap"]

  defp tab_trigger_classes(true, true, false),
    do: ["tab shrink-0 whitespace-nowrap tab-active tab-disabled"]

  defp tab_trigger_classes(false, true, false),
    do: ["tab shrink-0 whitespace-nowrap tab-disabled"]

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
