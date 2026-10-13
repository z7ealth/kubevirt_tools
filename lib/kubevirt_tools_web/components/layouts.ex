defmodule KubevirtToolsWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KubevirtToolsWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :any,
    default: nil,
    doc: "when set (e.g. signed in), navbar shows app version under the title"

  attr :navbar, :atom,
    default: :full,
    values: [:full, :theme_only],
    doc: ":theme_only shows only the theme toggle (e.g. sign-in page)"

  attr :main_class, :any,
    default: nil,
    doc: "extra classes merged onto <main> (e.g. full-bleed welcome screen)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex min-h-dvh flex-col">
      <.pp_top_app_bar
        id="app-top-bar"
        position="sticky"
        class="shrink-0 border-b border-pp-outline-variant/60 sm:px-4 lg:px-10"
      >
        <:leading :if={@navbar == :full}>
          <.link
            navigate={~p"/"}
            class="ms-2 flex shrink-0 items-center"
            aria-hidden="true"
            tabindex="-1"
          >
            <img
              src={~p"/images/kubevirt_tools_logo_no_bg.png"}
              class="h-9 w-auto max-w-[10rem] object-contain object-left"
              alt=""
            />
          </.link>
        </:leading>
        <.link
          :if={@navbar == :full}
          navigate={~p"/"}
          id="navbar-home-link"
          class="ms-2 hidden flex-col leading-tight transition-colors hover:text-pp-primary sm:flex"
        >
          <span class="pp-title-medium">KubeVirt Tools</span>
          <span
            :if={@current_scope}
            class="pp-label-small text-pp-on-surface-variant tabular-nums"
          >
            v{KubevirtTools.version_string()}
          </span>
        </.link>

        <:actions>
          <.pp_icon_button
            :if={@navbar == :full && @current_scope}
            icon="hero-bug-ant"
            label="Open GitHub Issues"
            href="https://github.com/z7ealth/kubevirt_tools/issues"
            target="_blank"
            rel="noopener noreferrer"
            id="navbar-github-issues-link"
          />
          <.pp_button
            :if={@navbar == :full && @current_scope}
            variant="text"
            href={~p"/session"}
            method="delete"
            id="navbar-sign-out"
            class="max-sm:hidden"
          >
            <:start_icon>
              <.icon name="hero-arrow-right-on-rectangle" class="size-[18px]" />
            </:start_icon>
            Sign out
          </.pp_button>
          <.pp_icon_button
            :if={@navbar == :full && @current_scope}
            icon="hero-arrow-right-on-rectangle"
            label="Sign out"
            href={~p"/session"}
            method="delete"
            id="navbar-sign-out-compact"
            class="sm:hidden"
          />
          <.pp_button
            :if={@navbar == :full && !@current_scope}
            navigate={~p"/login"}
            id="navbar-sign-in"
          >
            Sign in
          </.pp_button>
          <span class={["me-2", @navbar == :full && "ms-2 border-s border-pp-outline-variant ps-3"]}>
            <.theme_toggle />
          </span>
        </:actions>
      </.pp_top_app_bar>

      <main class={[
        "flex min-h-0 flex-1 flex-col space-y-4 px-4 py-10 sm:px-8 lg:px-14 overflow-x-hidden",
        @main_class
      ]}>
        {render_slot(@inner_block)}
      </main>

      <footer class="shrink-0 border-t border-pp-outline-variant/60 bg-pp-surface-container-low py-3 text-center">
        <.pp_button
          variant="text"
          color="secondary"
          href="https://github.com/z7ealth/kubevirt_tools"
          target="_blank"
          rel="noopener noreferrer"
          title="KubeVirt Tools on GitHub"
          id="footer-github-link"
        >
          <:start_icon>
            <svg
              class="size-[18px] shrink-0"
              viewBox="0 0 24 24"
              fill="currentColor"
              aria-hidden="true"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                fill-rule="evenodd"
                clip-rule="evenodd"
                d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
              />
            </svg>
          </:start_icon>
          GitHub
        </.pp_button>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group: Phoenix's `@flash` as MD3 snackbars (auto-hidden
  after 6s), plus the "connection lost" notices while the LiveView socket is
  disconnected.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <.pp_flash_group id={@id} flash={@flash} auto_hide_duration={6000} connection_notices />
    """
  end

  @doc """
  Provides the System / Light / Dark theme toggle (MD3 segmented control).

  It sets `data-theme` on `<html>` and persists the choice under
  `localStorage["phx:theme"]`; the `<head>` script in root.html.heex restores
  it before first paint.
  """
  def theme_toggle(assigns) do
    ~H"""
    <.pp_theme_toggle />
    """
  end
end
