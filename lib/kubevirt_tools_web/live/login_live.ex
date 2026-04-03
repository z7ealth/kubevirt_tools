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
        <div class="card w-full max-w-md border border-base-300/70 bg-base-100 shadow-xl shadow-base-300/10">
          <div class="card-body gap-6 p-6 sm:p-8">
            <div class="flex flex-col items-center text-center gap-3">
              <img
                src={~p"/images/kubevirt_tools_logo_no_bg.png"}
                class="h-24 w-auto max-w-[16rem] sm:h-28 sm:max-w-[18rem] object-contain object-center"
                alt="KubeVirt Tools"
              />
              <div>
                <h1 class="text-xl font-semibold tracking-tight text-base-content">Sign in</h1>
              </div>
            </div>

            <p class="text-sm text-base-content/70 leading-relaxed text-center">
              Your file stays in server memory for this session only and is not written to disk.
            </p>

            <form
              action={~p"/session"}
              method="post"
              enctype="multipart/form-data"
              class="space-y-5"
              id="kubeconfig-login-form"
            >
              <input type="hidden" name="_csrf_token" value={@csrf_token} />

              <div class="space-y-2">
                <label for="kubeconfig-file" class="block text-sm font-medium text-base-content/90">
                  Kubeconfig file
                </label>
                <p class="text-xs text-base-content/55">
                  Often at
                  <code class="px-1 rounded bg-base-200 font-mono text-[0.8rem]">~/.kube/config</code>
                  — choose “All files” in the picker if needed.
                </p>
                <input
                  type="file"
                  name="kubeconfig"
                  id="kubeconfig-file"
                  required
                  class={[
                    "file-input file-input-bordered w-full transition",
                    "hover:border-primary/50 focus:border-primary"
                  ]}
                />
              </div>

              <button
                type="submit"
                class="btn btn-primary w-full gap-2 transition hover:brightness-110 active:scale-[0.99]"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-5" /> Connect to cluster
              </button>
            </form>

            <p
              class="text-center text-[0.7rem] text-base-content/40 tabular-nums pt-2 border-t border-base-300/50"
              id="login-app-version"
            >
              KubeVirt Tools v{@app_version}
            </p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
