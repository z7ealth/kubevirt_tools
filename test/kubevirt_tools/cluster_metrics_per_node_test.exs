defmodule KubevirtTools.ClusterMetricsPerNodeTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.ClusterMetrics

  test "per_node_usage_pct returns CPU and memory percent when NodeMetrics matches" do
    nodes = [
      %{
        "metadata" => %{"name" => "n1"},
        "status" => %{"allocatable" => %{"cpu" => "2", "memory" => "4Gi"}}
      }
    ]

    metrics = [
      %{
        "metadata" => %{"name" => "n1"},
        "usage" => %{"cpu" => "500m", "memory" => "1Gi"}
      }
    ]

    assert %{"n1" => %{cpu: cpu, mem: mem}} = ClusterMetrics.per_node_usage_pct(nodes, metrics)
    assert cpu == "25%"
    assert mem == "25%"
  end

  test "per_node_usage_pct returns dashes when there is no metric for the node" do
    nodes = [%{"metadata" => %{"name" => "n1"}, "status" => %{}}]
    assert %{"n1" => %{cpu: "—", mem: "—"}} = ClusterMetrics.per_node_usage_pct(nodes, [])
  end
end
