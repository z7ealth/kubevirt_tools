defmodule KubevirtTools.PrometheusSetup do
  @moduledoc false

  @default_prometheus_url "http://prometheus-k8s.monitoring.svc.cluster.local:9090"

  @doc """
  Base URL for the Prometheus HTTP API as shown in dashboard copy.

  Set `PROMETHEUS_URL` to match your deployment (e.g. in-cluster Service or external URL).
  Default matches a common kube-prometheus-stack service name/namespace.
  """
  @spec base_url() :: String.t()
  def base_url do
    case System.get_env("PROMETHEUS_URL") do
      url when is_binary(url) -> String.trim(url)
      _ -> @default_prometheus_url
    end
  end

  @doc "Short note appended to setup hints so operators know which URL this UI assumes."
  @spec endpoint_env_hint() :: String.t()
  def endpoint_env_hint do
    "This UI references Prometheus at #{base_url()}—set PROMETHEUS_URL if your API is elsewhere " <>
      "(default assumes kube-prometheus-stack: prometheus-k8s.monitoring.svc)."
  end
end
