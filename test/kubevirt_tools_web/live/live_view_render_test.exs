defmodule KubevirtToolsWeb.LiveViewRenderTest do
  @moduledoc """
  Mounts the authed LiveViews and asserts the templates render. The cluster
  data loads async and fails to connect in test, which exercises the
  loading / :failed / error markup (the loading card and banner paths) —
  enough to catch a template that crashes at render time.
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
    {:ok, lv, html} = conn |> authed(token) |> live(~p"/dashboard")
    assert html =~ "KubeVirt Tools"
    assert has_element?(lv, "#app-top-bar[data-pp-component=top-app-bar]")
    assert has_element?(lv, "#flash-group[data-pp-component=flash-group]")
  end

  test "vm show renders", %{conn: conn, token: token} do
    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/vms/default/nope")
    assert has_element?(lv, "#vm-breadcrumbs a", "VMs")
  end

  test "node show renders", %{conn: conn, token: token} do
    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/nodes/nope")
    assert has_element?(lv, "#node-breadcrumbs a", "Nodes")
  end

  test "storage class, disk and network show render", %{conn: conn, token: token} do
    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/storage_classes/nope")
    assert has_element?(lv, "#storage-class-breadcrumbs")

    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/disks/default/vm/disk0")
    assert has_element?(lv, "#disk-breadcrumbs")

    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/networks/default/vm/eth0")
    assert has_element?(lv, "#network-breadcrumbs")
  end

  test "async failure renders the error banner", %{conn: conn, token: token} do
    {:ok, lv, _html} = conn |> authed(token) |> live(~p"/vms/default/nope")
    render_async(lv, 15_000)
    assert has_element?(lv, "[role=alert]", "Could not load this VM")
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
