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
      <header class={[
        "navbar shrink-0 border-b border-base-300/60 bg-base-100/90 backdrop-blur-md",
        "px-4 sm:px-8 lg:px-14",
        @navbar == :theme_only && "justify-end"
      ]}>
        <div :if={@navbar == :full} class="flex-1">
          <.link navigate={~p"/"} class="flex w-fit items-center gap-3 group">
            <img
              src={~p"/images/kubevirt_tools_logo_no_bg.png"}
              class="h-9 w-auto max-w-[10rem] shrink-0 object-contain object-left"
              alt="KubeVirt Tools"
            />
            <div class="flex flex-col leading-tight">
              <span class="text-sm font-semibold tracking-tight group-hover:text-primary transition-colors">
                KubeVirt Tools
              </span>
              <span :if={@current_scope} class="text-xs text-base-content/55 tabular-nums">
                v{KubevirtTools.version_string()}
              </span>
            </div>
          </.link>
        </div>
        <div class="flex-none">
          <ul class="flex items-center gap-1 sm:gap-2">
            <li :if={@navbar == :full && @current_scope}>
              <a
                href="https://github.com/z7ealth/kubevirt_tools/issues"
                class="btn btn-ghost btn-sm gap-1"
                target="_blank"
                rel="noopener noreferrer"
                title="Open GitHub Issues"
                id="navbar-github-issues-link"
              >
                <.icon name="hero-bug-ant" class="size-4 opacity-70" />
                <span class="hidden sm:inline">Issues</span>
              </a>
            </li>
            <li :if={@navbar == :full && @current_scope}>
              <.link href={~p"/session"} method="delete" class="btn btn-ghost btn-sm gap-1">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4 opacity-70" /> Sign out
              </.link>
            </li>
            <li :if={@navbar == :full && !@current_scope}>
              <.link navigate={~p"/login"} class="btn btn-primary btn-sm">Sign in</.link>
            </li>
            <li class={[@navbar == :full && "pl-2 border-l border-base-300/80"]}>
              <.theme_toggle />
            </li>
          </ul>
        </div>
      </header>

      <main class={[
        "flex min-h-0 flex-1 flex-col space-y-4 px-4 py-10 sm:px-8 lg:px-14 overflow-x-hidden",
        @main_class
      ]}>
        {render_slot(@inner_block)}
      </main>

      <footer class="shrink-0 border-t border-base-300/60 bg-base-100/85 py-5 text-center">
        <div class="inline-flex flex-wrap items-center justify-center gap-x-3 gap-y-2 text-sm text-base-content/65">
          <a
            href="https://github.com/z7ealth/kubevirt_tools"
            class="inline-flex items-center gap-2 transition-colors hover:text-primary"
            target="_blank"
            rel="noopener noreferrer"
            title="KubeVirt Tools on GitHub"
            id="footer-github-link"
          >
            <svg
              class="size-5 shrink-0 opacity-80"
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
            <span class="font-medium">GitHub</span>
          </a>
          <span class="text-base-content/35 select-none" aria-hidden="true">|</span>
          <a
            href="https://z7ealth.dev"
            class="inline-flex items-center gap-2 transition-colors hover:text-primary"
            target="_blank"
            rel="noopener noreferrer"
            title="z7ealth.dev"
            id="footer-website-link"
          >
            <.icon name="hero-globe-alt" class="size-5 shrink-0 opacity-80" />
            <span class="font-medium">z7ealth.dev</span>
          </a>
        </div>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        auto_dismiss={true}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        auto_dismiss={true}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
