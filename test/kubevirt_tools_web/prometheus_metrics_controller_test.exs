defmodule KubevirtToolsWeb.PrometheusMetricsControllerTest do
  use KubevirtToolsWeb.ConnCase, async: true

  test "GET /metrics returns Prometheus text exposition", %{conn: conn} do
    conn = get(conn, ~p"/metrics")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    assert conn.resp_body =~ "kubevirt_tools_info"
    assert conn.resp_body =~ "kubevirt_tools_http_scrape_ok"
  end
end
