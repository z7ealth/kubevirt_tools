defmodule KubevirtToolsWeb.LoginLive do
  use KubevirtToolsWeb, :live_view

  alias KubevirtTools

  on_mount {KubevirtToolsWeb.AuthHooks, :redirect_if_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())
     |> assign(:app_version, KubevirtTools.version_string())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={nil} navbar={:theme_only}>
      <div class="flex w-full flex-1 flex-col items-center justify-center px-4 py-10 sm:py-14">
        <.pp_card variant="elevated" class="w-full max-w-md" id="login-card">
          <div class="flex flex-col gap-6 sm:p-2">
            <div class="flex flex-col items-center text-center gap-3">
              <img
                src={~p"/images/kubevirt_tools_logo_no_bg.png"}
                class="h-24 w-auto max-w-[16rem] sm:h-28 sm:max-w-[18rem] object-contain object-center"
                alt="KubeVirt Tools"
              />
              <.pp_typography variant="headline-small">Sign in</.pp_typography>
            </div>

            <.pp_typography variant="body-medium" color="on-surface-variant" class="text-center">
              Your file stays in server memory for this session only and is not written to disk.
            </.pp_typography>

            <form
              action={~p"/session"}
              method="post"
              enctype="multipart/form-data"
              class="space-y-5"
              id="kubeconfig-login-form"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />

              <div class="space-y-2">
                <label for="kubeconfig-file" class="block pp-title-small text-pp-on-surface">
                  Kubeconfig file
                </label>
                <p class="pp-body-small text-pp-on-surface-variant">
                  Often at
                  <code class="px-1 rounded-pp-xs bg-pp-surface-container-highest font-mono">
                    ~/.kube/config
                  </code>
                  — choose “All files” in the picker if needed.
                </p>
                <input
                  type="file"
                  name="kubeconfig"
                  id="kubeconfig-file"
                  required
                  class={[
                    "block w-full cursor-pointer rounded-pp-xs border border-pp-outline bg-pp-surface",
                    "pp-body-medium text-pp-on-surface-variant pp-motion-effects-fast",
                    "file:me-3 file:h-10 file:cursor-pointer file:rounded-s-pp-xs file:border-0",
                    "file:bg-pp-secondary-container file:px-4 file:pp-label-large file:text-pp-on-secondary-container",
                    "hover:border-pp-on-surface focus:outline-2 focus:outline-pp-primary focus:-outline-offset-1"
                  ]}
                />
              </div>

              <.pp_button type="submit" size="md" class="w-full" id="kubeconfig-login-submit">
                <:start_icon>
                  <.icon name="hero-arrow-right-on-rectangle" class="size-6" />
                </:start_icon>
                Connect to cluster
              </.pp_button>
            </form>

            <.pp_typography
              variant="body-small"
              color="on-surface-variant"
              class="text-center tabular-nums pt-3 border-t border-pp-outline-variant"
              id="login-app-version"
            >
              KubeVirt Tools v{@app_version}
            </.pp_typography>
          </div>
        </.pp_card>
      </div>
    </Layouts.app>
    """
  end
end
