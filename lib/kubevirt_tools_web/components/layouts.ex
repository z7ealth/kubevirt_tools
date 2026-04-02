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
    doc: "optional UI scope (e.g. cluster session label for the signed-in user)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar border-b border-base-300/60 bg-base-100/90 backdrop-blur-md px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-3 group">
          <img src={~p"/images/logo.svg"} width="36" alt="" />
          <div class="flex flex-col leading-tight">
            <span class="text-sm font-semibold tracking-tight group-hover:text-primary transition-colors">
              KubeVirt Tools
            </span>
            <span
              :if={@current_scope && Map.get(@current_scope, :label)}
              class="text-xs text-base-content/55"
            >
              {Map.get(@current_scope, :label)}
            </span>
          </div>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex items-center gap-1 sm:gap-2">
          <li>
            <.link navigate={~p"/dashboard"} class="btn btn-ghost btn-sm">
              Dashboard
            </.link>
          </li>
          <li :if={@current_scope}>
            <.link href={~p"/session"} method="delete" class="btn btn-ghost btn-sm gap-1">
              <.icon name="hero-arrow-right-on-rectangle" class="size-4 opacity-70" /> Sign out
            </.link>
          </li>
          <li :if={!@current_scope}>
            <.link navigate={~p"/login"} class="btn btn-primary btn-sm">Sign in</.link>
          </li>
          <li class="pl-2 border-l border-base-300/80">
            <.theme_toggle />
          </li>
        </ul>
      </div>
    </header>

    <main class="min-w-0 space-y-4 px-4 py-10 sm:px-8 lg:px-14 min-h-[calc(100vh-5rem)] overflow-x-hidden">
      {render_slot(@inner_block)}
    </main>

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
