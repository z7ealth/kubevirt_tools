defmodule KubevirtToolsWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  These are thin wrappers over [PhoenixPaper](https://hexdocs.pm/phoenix_paper)
  (`pp_*` Material Design function components) — the app's UI layer was migrated
  to PhoenixPaper while keeping daisyUI installed for the charts, topology and
  welcome-screen theming. See `assets/css/app.css` for how PhoenixPaper's
  `--color-pp-*` tokens are pointed at the daisyUI (kubevirt teal) palette.

  Useful references:

    * [PhoenixPaper](https://hexdocs.pm/phoenix_paper) - the component library.
    * [Tailwind CSS](https://tailwindcss.com) - layout / sizing / spacing.
    * [Heroicons](https://heroicons.com) - see `icon/1`.
    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html)
  """
  use Phoenix.Component
  use PhoenixPaper.Components

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices as a PhoenixPaper alert in a top-end toast.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :auto_dismiss, :boolean, default: true, doc: "clear flash when the progress animation ends"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <%= if msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind) do %>
      <div
        id={@id}
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
        phx-hook=".FlashAutoDismiss"
        data-flash-kind={if(@auto_dismiss, do: to_string(@kind))}
        role="alert"
        class="toast toast-top toast-end z-50"
        {@rest}
      >
        <div class="relative w-80 sm:w-96 max-w-80 sm:max-w-96 overflow-hidden">
          <.pp_alert severity={severity(@kind)} variant="standard" class="shadow-lg pr-2">
            <:title :if={@title}>{@title}</:title>
            {msg}
            <:action>
              <button type="button" class="group shrink-0 cursor-pointer" aria-label="close">
                <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
              </button>
            </:action>
          </.pp_alert>
          <div
            :if={@auto_dismiss}
            class="pointer-events-none absolute inset-x-0 bottom-0 h-0.5 bg-pp-on-surface/10"
            aria-hidden="true"
          >
            <div class="flash-progress-bar-fill h-full w-full bg-pp-primary" />
          </div>
        </div>
      </div>
      <script :if={@auto_dismiss} :type={Phoenix.LiveView.ColocatedHook} name=".FlashAutoDismiss">
        export default {
          mounted() {
            const bar = this.el.querySelector(".flash-progress-bar-fill")
            const kind = this.el.dataset.flashKind
            if (!bar || !kind) return

            this._dismissed = false
            const dismiss = () => {
              if (this._dismissed) return
              this._dismissed = true
              if (this._timer) window.clearTimeout(this._timer)
              this._timer = null
              this.pushEvent("lv:clear-flash", { key: kind })
              this.js().hide(this.el)
            }

            /* Must match `flash-progress-bar` duration in app.css (6s). */
            const durationMs = 6000

            this._onAnimationEnd = (e) => {
              if (e.target !== bar) return
              if (e.animationName && e.animationName !== "flash-progress-bar") return
              dismiss()
            }

            const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
            if (reduced) {
              this._timer = window.setTimeout(dismiss, durationMs)
            } else {
              bar.addEventListener("animationend", this._onAnimationEnd)
              this._timer = window.setTimeout(dismiss, durationMs)
            }
          },
          destroyed() {
            if (this._timer) window.clearTimeout(this._timer)
            const bar = this.el.querySelector(".flash-progress-bar-fill")
            if (bar && this._onAnimationEnd) {
              bar.removeEventListener("animationend", this._onAnimationEnd)
            }
          }
        }
      </script>
    <% end %>
    """
  end

  defp severity(:info), do: "info"
  defp severity(:error), do: "error"

  @doc """
  Renders a button, backed by `PhoenixPaper.Button.pp_button/1`.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  attr :class, :any, default: nil
  attr :variant, :string, default: nil, doc: ~s|"primary" for a raised button, nil for flat|
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns, :pp_variant, if(assigns.variant == "primary", do: "raised", else: "flat"))

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link
        class={[
          "inline-flex items-center justify-center gap-2 rounded-full px-6 py-2.5 text-sm font-medium uppercase tracking-wide",
          "bg-pp-primary text-pp-on-primary transition hover:brightness-110",
          @class
        ]}
        {@rest}
      >
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <.pp_button
        variant={@pp_variant}
        color="primary"
        type={@rest[:type] || "button"}
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:type, :disabled, :href, :navigate, :patch, :method, :download])}
      >
        {render_slot(@inner_block)}
      </.pp_button>
      """
    end
  end

  @doc """
  Renders an input, backed by the PhoenixPaper form components.

  A `Phoenix.HTML.FormField` may be passed as `field`, otherwise pass `name`,
  `value` and friends explicitly. `type="select"` renders `pp_select/1`,
  `type="checkbox"` renders `pp_checkbox/1`, everything else `pp_input/1`.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to pp_select/1"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil
  attr :rows, :integer, default: 3

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="mb-2">
      <.pp_checkbox
        id={@id}
        name={@name}
        label={@label}
        checked={@checked}
        disabled={!!@rest[:disabled]}
        class={@class}
      />
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_select
        id={@id}
        name={@name}
        label={@label}
        value={@value}
        prompt={@prompt}
        options={@options}
        errors={@errors}
        class={@class}
        {@rest}
      />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_input
        multiline
        rows={@rows}
        id={@id}
        name={@name}
        label={@label}
        value={Phoenix.HTML.Form.normalize_value("textarea", @value)}
        errors={@errors}
        class={@class}
        {@rest}
      />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_input
        type={@type}
        id={@id}
        name={@name}
        label={@label}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        errors={@errors}
        class={@class}
        {@rest}
      />
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  attr :rest, :global
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-pp-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title, subtitle and actions.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4", @class]}>
      <div>
        <.pp_typography variant="h5" class="leading-8">
          {render_slot(@inner_block)}
        </.pp_typography>
        <.pp_typography :if={@subtitle != []} variant="body2" class="text-pp-on-surface/70">
          {render_slot(@subtitle)}
        </.pp_typography>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table, backed by the PhoenixPaper table components.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <.pp_table_container>
      <.pp_table dense>
        <.pp_table_head>
          <.pp_table_row>
            <.pp_table_cell :for={col <- @col} variant="head">{col[:label]}</.pp_table_cell>
            <.pp_table_cell :if={@action != []} variant="head">
              <span class="sr-only">Actions</span>
            </.pp_table_cell>
          </.pp_table_row>
        </.pp_table_head>
        <.pp_table_body
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
        >
          <.pp_table_row :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <.pp_table_cell
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "hover:cursor-pointer"}
            >
              {render_slot(col, @row_item.(row))}
            </.pp_table_cell>
            <.pp_table_cell :if={@action != []} class="w-0 font-semibold">
              <div class="flex gap-4">
                {for action <- @action, do: render_slot(action, @row_item.(row))}
              </div>
            </.pp_table_cell>
          </.pp_table_row>
        </.pp_table_body>
      </.pp_table>
    </.pp_table_container>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-x-8 gap-y-3 list-none p-0 m-0">
      <li :for={item <- @item} class="border-b border-pp-outline/30 pb-2">
        <div class="font-bold">{item.title}</div>
        <div>{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini. By default the
  outline style is used; `-solid` and `-mini` suffixes switch styles.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message.
  """
  def translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
