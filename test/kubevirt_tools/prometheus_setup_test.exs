defmodule KubevirtTools.PrometheusSetupTest do
  use ExUnit.Case, async: false

  setup do
    prev = System.get_env("PROMETHEUS_URL")
    on_exit(fn -> restore_env("PROMETHEUS_URL", prev) end)
    :ok
  end

  test "base_url falls back to kube-prometheus-stack-style default" do
    System.delete_env("PROMETHEUS_URL")

    assert KubevirtTools.PrometheusSetup.base_url() ==
             "http://prometheus-k8s.monitoring.svc.cluster.local:9090"
  end

  test "base_url reads PROMETHEUS_URL when set" do
    System.put_env("PROMETHEUS_URL", " http://prometheus.example:9090 ")
    assert KubevirtTools.PrometheusSetup.base_url() == "http://prometheus.example:9090"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, val), do: System.put_env(key, val)
end
