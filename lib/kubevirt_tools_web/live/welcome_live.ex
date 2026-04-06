defmodule KubevirtToolsWeb.WelcomeLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :require_kubeconfig}

  alias KubevirtTools

  @auto_redirect_ms 2_900

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Welcome")
      |> assign(:app_version, KubevirtTools.version_string())
      |> assign(:welcome_timer_ref, nil)

    socket =
      if connected?(socket) do
        ref = Process.send_after(self(), :welcome_continue, @auto_redirect_ms)
        assign(socket, :welcome_timer_ref, ref)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("skip_welcome", _params, socket) do
    socket = cancel_welcome_timer(socket)

    {:noreply,
     socket
     |> put_flash(:info, "Connected to the cluster.")
     |> push_navigate(to: ~p"/dashboard")}
  end

  @impl true
  def handle_info(:welcome_continue, socket) do
    socket = cancel_welcome_timer(socket)

    {:noreply,
     socket
     |> put_flash(:info, "Connected to the cluster.")
     |> push_navigate(to: ~p"/dashboard")}
  end

  defp cancel_welcome_timer(socket) do
    case socket.assigns.welcome_timer_ref do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    assign(socket, :welcome_timer_ref, nil)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{}}
      main_class="!p-0 !space-y-0 flex-1 min-h-0 overflow-hidden"
    >
      <div
        class={[
          "welcome-screen relative flex min-h-0 flex-1 flex-col items-center justify-center",
          "overflow-hidden px-6 py-12 sm:px-10"
        ]}
        id="welcome-screen-root"
      >
        <div
          class="welcome-screen__aurora pointer-events-none absolute inset-0 opacity-90"
          aria-hidden="true"
        >
        </div>
        <div
          class="welcome-screen__grid pointer-events-none absolute inset-0 opacity-[0.07]"
          aria-hidden="true"
        >
        </div>

        <div class="relative z-10 flex max-w-lg flex-col items-center text-center">
          <div class="welcome-screen__logo-wrap mb-8 sm:mb-10">
            <img
              src={~p"/images/kubevirt_tools_logo_no_bg.png"}
              class="welcome-screen__logo mx-auto h-32 w-auto max-w-[min(100%,18rem)] object-contain drop-shadow-lg sm:h-40 sm:max-w-[22rem]"
              alt="KubeVirt Tools"
              decoding="async"
            />
          </div>
          <h1 class="welcome-screen__title font-semibold tracking-tight text-base-content">
            <span class="welcome-screen__title-line block text-3xl sm:text-4xl md:text-5xl">
              KubeVirt Tools
            </span>
            <span class="welcome-screen__subtitle mt-3 block text-sm font-medium uppercase tracking-[0.22em] text-primary/90 sm:text-base">
              Welcome
            </span>
          </h1>
          <p class="welcome-screen__version mt-2 text-xs tabular-nums text-base-content/40">
            v{@app_version}
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
