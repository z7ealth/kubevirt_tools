defmodule KubevirtToolsWeb.LoginLive do
  use KubevirtToolsWeb, :live_view

  on_mount {KubevirtToolsWeb.AuthHooks, :redirect_if_authenticated}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:csrf_token, Plug.CSRFProtection.get_csrf_token())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={nil}>
      <div class="rounded-2xl border border-base-300/80 bg-base-100/80 shadow-lg shadow-base-300/20 backdrop-blur-sm px-8 py-10 sm:px-10">
        <div class="flex items-center gap-3 mb-2">
          <div class="flex size-11 items-center justify-center rounded-xl bg-primary/15 text-primary">
            <.icon name="hero-cpu-chip" class="size-6" />
          </div>
          <div>
            <h1 class="text-xl font-semibold tracking-tight">KubeVirt Tools</h1>
            <p class="text-sm text-base-content/60">Upload your kubeconfig to connect</p>
          </div>
        </div>

        <p class="mt-6 text-sm text-base-content/70 leading-relaxed">
          Your file is kept in server memory for this session only and is not written to disk.
          Use a dedicated service account with read-only access when possible.
        </p>

        <form
          action={~p"/session"}
          method="post"
          enctype="multipart/form-data"
          class="mt-8 space-y-6"
          id="kubeconfig-login-form"
        >
          <input type="hidden" name="_csrf_token" value={@csrf_token} />

          <div>
            <label for="kubeconfig-file" class="block text-sm font-medium text-base-content/90 mb-2">
              Kubeconfig file
            </label>
            <p class="text-xs text-base-content/55 mb-2">
              Default location is often <code class="px-1 rounded bg-base-200 font-mono text-[0.8rem]">.kube/config</code>
              (no extension). Use “All files” in the file dialog if your browser filters the list.
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
      </div>
    </Layouts.app>
    """
  end
end
