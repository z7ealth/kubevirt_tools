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
        <.pp_card elevation={3} class="w-full max-w-md">
          <div class="flex flex-col gap-6 p-2 sm:p-4">
            <div class="flex flex-col items-center text-center gap-3">
              <img
                src={~p"/images/kubevirt_tools_logo_no_bg.png"}
                class="h-24 w-auto max-w-[16rem] sm:h-28 sm:max-w-[18rem] object-contain object-center"
                alt="KubeVirt Tools"
              />
              <.pp_typography variant="h5" class="tracking-tight">Sign in</.pp_typography>
            </div>

            <.pp_typography variant="body2" class="text-pp-on-surface/70 leading-relaxed text-center">
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
                <label for="kubeconfig-file" class="block text-sm font-medium text-pp-on-surface/90">
                  Kubeconfig file
                </label>
                <p class="text-xs text-pp-on-surface/55">
                  Often at
                  <code class="px-1 rounded bg-pp-surface-variant font-mono text-[0.8rem]">
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
                    "block w-full rounded-sm border border-pp-outline bg-pp-surface text-sm transition",
                    "file:mr-3 file:border-0 file:bg-pp-primary file:px-4 file:py-2 file:text-pp-on-primary file:font-medium",
                    "hover:border-pp-primary/50 focus:border-pp-primary focus:outline-none"
                  ]}
                />
              </div>

              <.pp_button type="submit" color="primary" class="w-full">
                <:start_icon>
                  <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
                </:start_icon>
                Connect to cluster
              </.pp_button>
            </form>

            <.pp_typography
              variant="caption"
              class="block text-center text-pp-on-surface/40 tabular-nums pt-2 border-t border-pp-outline/40"
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
