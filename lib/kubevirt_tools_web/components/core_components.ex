defmodule KubevirtToolsWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  These are thin wrappers over [PhoenixPaper](https://hexdocs.pm/phoenix_paper)
  (`pp_*` Material Design 3 function components), plus a few app-level
  composites built only from MD3 parts for what MD3 leaves open (banners,
  status chips, loading placeholders). daisyUI stays installed only for the
  theme variables the charts, topology and welcome screen read.

  Colors come from the MD3 scheme in `assets/css/phoenix_paper_theme.css`
  (generated from the kubevirt.io teal), plus the app-level `app-warning`
  custom color defined in `assets/css/app.css`.

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
  Renders a button, backed by `PhoenixPaper.Button.pp_button/1`.

  Passing `href`, `navigate` or `patch` renders a link with the same look.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type form)

  attr :class, :any, default: nil
  attr :variant, :string, default: nil, doc: ~s|"primary" for a filled button, nil for tonal|
  slot :inner_block, required: true

  def button(assigns) do
    assigns =
      assign(assigns, :pp_variant, if(assigns.variant == "primary", do: "filled", else: "tonal"))

    ~H"""
    <.pp_button variant={@pp_variant} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </.pp_button>
    """
  end

  @doc """
  Renders an input, backed by the PhoenixPaper form components.

  A `Phoenix.HTML.FormField` may be passed as `field`, otherwise pass `name`,
  `value` and friends explicitly. `type="select"` renders `pp_select/1`,
  `type="checkbox"` `pp_checkbox/1`, `type="password"` `pp_password_field/1`,
  `type="number"` `pp_number_field/1`, everything else `pp_text_field/1`.
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
        error={@errors != []}
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
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:disabled])}
      />
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_text_field
        multiline
        rows={@rows}
        id={@id}
        name={@name}
        label={@label}
        value={Phoenix.HTML.Form.normalize_value("textarea", @value)}
        errors={@errors}
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:disabled])}
      />
    </div>
    """
  end

  def input(%{type: "password"} = assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_password_field
        id={@id}
        name={@name}
        label={@label}
        value={@value}
        errors={@errors}
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:disabled])}
      />
    </div>
    """
  end

  def input(%{type: "number"} = assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_number_field
        id={@id}
        name={@name}
        label={@label}
        value={Phoenix.HTML.Form.normalize_value("number", @value)}
        errors={@errors}
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:disabled])}
      />
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-2">
      <.pp_text_field
        type={@type}
        id={@id}
        name={@name}
        label={@label}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        errors={@errors}
        disabled={!!@rest[:disabled]}
        class={@class}
        {Map.drop(@rest, [:disabled])}
      />
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  attr :rest, :global
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center pp-body-small text-pp-error" {@rest}>
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
        <.pp_typography variant="headline-small">
          {render_slot(@inner_block)}
        </.pp_typography>
        <.pp_typography :if={@subtitle != []} variant="body-medium" color="on-surface-variant">
          {render_slot(@subtitle)}
        </.pp_typography>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a page title: an optional eyebrow, an MD3 headline with a leading
  icon and trailing status chips, and an optional supporting line.

  ## Examples

      <.page_title icon="hero-server-stack">
        {node.name}
        <:chips><.status_chip tone={:ok}>Ready</.status_chip></:chips>
      </.page_title>
  """
  attr :icon, :string, default: nil
  attr :eyebrow, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :chips
  slot :subtitle

  def page_title(assigns) do
    ~H"""
    <div class={["min-w-0", @class]}>
      <p :if={@eyebrow} class="pp-label-medium text-pp-primary">{@eyebrow}</p>
      <h1 class="flex flex-wrap items-center gap-3 pp-headline-small text-pp-on-surface">
        <.icon :if={@icon} name={@icon} class="size-7 text-pp-primary" />
        <span class="min-w-0 break-words">{render_slot(@inner_block)}</span>
        {render_slot(@chips)}
      </h1>
      <p :if={@subtitle != []} class="mt-1 pp-body-medium text-pp-on-surface-variant">
        {render_slot(@subtitle)}
      </p>
    </div>
    """
  end

  @doc """
  Renders a section heading (MD3 `title-large`) with a leading icon.
  """
  attr :icon, :string, default: nil
  attr :tag, :string, default: "h2", values: ~w(h2 h3)
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def section_title(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "flex items-center gap-2 text-pp-on-surface",
        if(@tag == "h2", do: "pp-title-large", else: "pp-title-medium"),
        @class
      ]}
    >
      <.icon :if={@icon} name={@icon} class="size-6 text-pp-primary" />
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @doc """
  Renders a banner: an inline, persistent message on a container color.

  MD3 has no alert component (PhoenixPaper 0.5 removed `Alert`); this is a
  composite of MD3 parts — a `-container` color role, `lg` corners, a
  leading icon and `body-medium` text. `:error` uses MD3's error container,
  `:warning` the app's `app-warning` custom color, `:info` the secondary
  container.

  ## Examples

      <.banner kind={:error}>Could not load cluster data.</.banner>
      <.banner kind={:warning} title="Prometheus not detected">Set PROMETHEUS_URL.</.banner>
  """
  attr :kind, :atom, default: :info, values: [:info, :warning, :error]
  attr :title, :string, default: nil
  attr :icon, :string, default: nil, doc: "overrides the kind's default icon"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def banner(assigns) do
    assigns = assign(assigns, :icon, assigns.icon || banner_icon(assigns.kind))

    ~H"""
    <div
      role={if(@kind == :error, do: "alert", else: "status")}
      class={[
        "flex items-start gap-3 rounded-pp-lg px-4 py-3 pp-body-medium",
        banner_colors(@kind),
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="mt-0.5 size-5 shrink-0" />
      <div class="min-w-0">
        <p :if={@title} class="pp-title-small">{@title}</p>
        <div class={[@title && "mt-0.5"]}>{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  defp banner_colors(:info), do: "bg-pp-secondary-container text-pp-on-secondary-container"
  defp banner_colors(:warning), do: "bg-app-warning-container text-app-on-warning-container"
  defp banner_colors(:error), do: "bg-pp-error-container text-pp-on-error-container"

  defp banner_icon(:info), do: "hero-information-circle"
  defp banner_icon(:warning), do: "hero-exclamation-triangle"
  defp banner_icon(:error), do: "hero-exclamation-circle"

  @doc """
  Renders a non-interactive MD3 input chip whose leading icon carries a
  status tone. MD3 chips have one color scheme, so the status lives in the
  icon (and its text alternative), not in a colored chip.

  Tones: `:ok`, `:warning`, `:error`, `:stopped`, `:info`, `:neutral`.

  ## Examples

      <.status_chip tone={:ok}>Ready</.status_chip>
      <.status_chip tone={:neutral} icon="hero-star-mini" selected>default</.status_chip>
  """
  attr :tone, :atom, default: :neutral, values: [:ok, :warning, :error, :stopped, :info, :neutral]
  attr :icon, :string, default: nil, doc: "overrides the tone's default icon"
  attr :selected, :boolean, default: false, doc: "MD3's selected (secondary-container) chip"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def status_chip(assigns) do
    assigns = assign(assigns, :icon, assigns.icon || tone_icon(assigns.tone))

    ~H"""
    <.pp_chip
      variant="input"
      selected={@selected}
      class={["h-7 shrink-0 align-middle", @class]}
      {@rest}
    >
      <:icon :if={@icon}><.icon name={@icon} class={tone_text_class(@tone)} /></:icon>
      {render_slot(@inner_block)}
    </.pp_chip>
    """
  end

  defp tone_icon(:ok), do: "hero-check-circle-mini"
  defp tone_icon(:warning), do: "hero-exclamation-triangle-mini"
  defp tone_icon(:error), do: "hero-x-circle-mini"
  defp tone_icon(:stopped), do: "hero-stop-circle-mini"
  defp tone_icon(:info), do: "hero-clock-mini"
  defp tone_icon(:neutral), do: nil

  @doc """
  The text color class for a status tone (see `status_chip/1`). Classes are
  literal strings so Tailwind's scanner finds them.
  """
  def tone_text_class(:ok), do: "text-pp-primary"
  def tone_text_class(:warning), do: "text-app-warning"
  def tone_text_class(:error), do: "text-pp-error"
  def tone_text_class(:stopped), do: "text-stopped"
  def tone_text_class(:info), do: "text-pp-tertiary"
  def tone_text_class(:neutral), do: "text-pp-on-surface-variant"
  def tone_text_class(:muted), do: "text-pp-on-surface-variant/60"

  @doc """
  Renders a loading placeholder: MD3's Expressive loading indicator on a
  filled card.
  """
  attr :label, :string, required: true
  attr :class, :any, default: nil
  attr :rest, :global

  def loading_card(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-4 rounded-pp-md bg-pp-surface-container px-5 py-10",
        "pp-body-large text-pp-on-surface-variant",
        @class
      ]}
      {@rest}
    >
      <.pp_loading_indicator size={40} label={@label} />
      <span>{@label}</span>
    </div>
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
    <.pp_table_container variant="outlined">
      <.pp_table>
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
            <.pp_table_cell :if={@action != []} class="w-0">
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
  Renders a data list on an outlined MD3 card.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil

  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <.pp_card id={@id} variant="outlined" class={@class}>
      <dl class="grid grid-cols-1 gap-x-8 gap-y-1 sm:grid-cols-2 xl:grid-cols-3">
        <div
          :for={item <- @item}
          class="min-w-0 border-b border-pp-outline-variant py-2.5"
        >
          <dt class="pp-label-medium text-pp-on-surface-variant">{item.title}</dt>
          <dd class="mt-0.5 pp-body-large text-pp-on-surface break-words">{render_slot(item)}</dd>
        </div>
      </dl>
    </.pp_card>
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
