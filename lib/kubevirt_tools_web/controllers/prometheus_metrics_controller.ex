defmodule KubevirtToolsWeb.PrometheusMetricsController do
  use KubevirtToolsWeb, :controller

  @doc """
  Prometheus text exposition format for scraping (add this URL as a static_configs target).
  """
  def index(conn, _params) do
    body = prometheus_text()

    conn
    |> put_resp_content_type("text/plain; version=0.0.4; charset=utf-8")
    |> send_resp(200, body)
  end

  defp prometheus_text do
    v =
      Application.spec(:kubevirt_tools, :vsn)
      |> to_string()
      |> String.replace(~r/["\\\n]/, "")

    """
    # HELP kubevirt_tools_info KubeVirt tools application marker (scrape health).
    # TYPE kubevirt_tools_info gauge
    kubevirt_tools_info{version="#{v}"} 1
    # HELP kubevirt_tools_http_scrape_ok Always 1 when this metrics endpoint is scraped successfully.
    # TYPE kubevirt_tools_http_scrape_ok gauge
    kubevirt_tools_http_scrape_ok 1
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end
end
