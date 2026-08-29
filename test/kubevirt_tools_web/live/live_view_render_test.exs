defmodule KubevirtToolsWeb.LiveViewRenderTest do
  @moduledoc """
  Mounts the authed LiveViews and asserts the templates render. The cluster
  data loads async and fails to connect in test, which exercises the
  loading / :failed / error markup (the pp_alert / pp_paper paths) — enough
  to catch a template that crashes at render time.
  """
  use KubevirtToolsWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    {:ok, token} = KubevirtTools.KubeconfigStore.put(sample_kubeconfig())
    on_exit(fn -> KubevirtTools.KubeconfigStore.delete(token) end)
    {:ok, token: token}
  end

  defp authed(conn, token), do: Plug.Test.init_test_session(conn, %{"kubevirt_token" => token})

  test "dashboard renders", %{conn: conn, token: token} do
    {:ok, _lv, html} = conn |> authed(token) |> live(~p"/dashboard")
    assert html =~ "KubeVirt Tools"
    assert html =~ "data-pp-component"
  end

  test "vm show renders", %{conn: conn, token: token} do
    {:ok, _lv, html} = conn |> authed(token) |> live(~p"/vms/default/nope")
    assert html =~ "Back to VMs"
  end

  test "node show renders", %{conn: conn, token: token} do
    {:ok, _lv, html} = conn |> authed(token) |> live(~p"/nodes/nope")
    assert html =~ "Back to Nodes"
  end

  defp sample_kubeconfig do
    """
    apiVersion: v1
    kind: Config
    clusters:
    - name: test
      cluster:
        server: https://127.0.0.1:59999
        insecure-skip-tls-verify: true
    contexts:
    - name: test
      context:
        cluster: test
        user: test
    current-context: test
    users:
    - name: test
      user:
        token: abc123
    """
  end
end
