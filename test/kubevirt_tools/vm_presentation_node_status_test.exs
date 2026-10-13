defmodule KubevirtTools.VmPresentationNodeStatusTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.VmPresentation

  defp build_node(ready_status, unschedulable \\ false) do
    conditions =
      case ready_status do
        nil -> [%{"type" => "MemoryPressure", "status" => "False"}]
        status -> [%{"type" => "Ready", "status" => status}]
      end

    %{
      "metadata" => %{"name" => "n1"},
      "spec" => if(unschedulable, do: %{"unschedulable" => true}, else: %{}),
      "status" => %{"conditions" => conditions}
    }
  end

  test "node_status/1 matches kubectl get nodes" do
    assert VmPresentation.node_status(build_node("True")) == "Ready"
    assert VmPresentation.node_status(build_node("True", true)) == "Ready,SchedulingDisabled"
    assert VmPresentation.node_status(build_node("False")) == "NotReady"
    assert VmPresentation.node_status(build_node("Unknown")) == "NotReady"
    assert VmPresentation.node_status(build_node("False", true)) == "NotReady,SchedulingDisabled"
    assert VmPresentation.node_status(build_node(nil)) == "Unknown"
    assert VmPresentation.node_status(build_node(nil, true)) == "Unknown,SchedulingDisabled"
  end

  test "node_status_tone/1" do
    assert VmPresentation.node_status_tone("Ready") == :ok
    assert VmPresentation.node_status_tone("Ready,SchedulingDisabled") == :warning
    assert VmPresentation.node_status_tone("NotReady") == :error
    assert VmPresentation.node_status_tone("NotReady,SchedulingDisabled") == :error
    assert VmPresentation.node_status_tone("Unknown") == :error
  end
end
