defmodule KubevirtTools.VmTopologyTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.VmTopology

  test "build/1 links VMs to hosts via VMI nodeName" do
    data = %{
      nodes: [
        %{"metadata" => %{"name" => "node-a"}},
        %{"metadata" => %{"name" => "node-b"}}
      ],
      vms: [
        %{"metadata" => %{"namespace" => "ns", "name" => "vm1"}},
        %{"metadata" => %{"namespace" => "ns", "name" => "vm2"}}
      ],
      vmis: [
        %{
          "metadata" => %{"namespace" => "ns", "name" => "vm1"},
          "status" => %{"nodeName" => "node-a", "phase" => "Running"}
        }
      ]
    }

    topo = VmTopology.build(data)

    assert topo["summary"]["nodes"] == 2
    assert topo["summary"]["vms"] == 2

    ids = Enum.map(topo["nodes"], & &1["id"])

    assert "host:node-a" in ids
    assert "host:node-b" in ids
    assert "vm:ns/vm1" in ids
    assert "vm:ns/vm2" in ids

    edges = topo["edges"]
    assert Enum.any?(edges, &(&1["from"] == "host:node-a" and &1["to"] == "vm:ns/vm1"))
    assert Enum.any?(edges, &(&1["from"] == "host:__unscheduled__" and &1["to"] == "vm:ns/vm2"))

    unsched =
      Enum.find(topo["nodes"], &(&1["id"] == "host:__unscheduled__"))

    assert unsched["hostStatus"] == "unscheduled"
  end

  test "build/1 treats VM without VMI and no printable as stopped (Unscheduled soft red)" do
    data = %{
      nodes: [%{"metadata" => %{"name" => "node-a"}}],
      vms: [
        %{"metadata" => %{"namespace" => "ns", "name" => "fedora-vm"}}
      ],
      vmis: []
    }

    topo = VmTopology.build(data)
    v = Enum.find(topo["nodes"], &(&1["id"] == "vm:ns/fedora-vm"))
    assert v["vmStatus"] == "stopped"

    assert Enum.any?(
             topo["edges"],
             &(&1["from"] == "host:__unscheduled__" and &1["to"] == "vm:ns/fedora-vm")
           )
  end

  test "build/1 keeps provisioning without VMI as other" do
    data = %{
      nodes: [],
      vms: [
        %{
          "metadata" => %{"namespace" => "ns", "name" => "v"},
          "status" => %{"printableStatus" => "Provisioning"}
        }
      ],
      vmis: []
    }

    topo = VmTopology.build(data)
    v = Enum.find(topo["nodes"], &(&1["id"] == "vm:ns/v"))
    assert v["vmStatus"] == "other"
  end

  test "build/1 maps stopping-like printableStatus to vm stopped" do
    data = %{
      nodes: [],
      vms: [
        %{
          "metadata" => %{"namespace" => "ns", "name" => "v"},
          "status" => %{"printableStatus" => "Stopping"}
        }
      ],
      vmis: []
    }

    topo = VmTopology.build(data)
    v = Enum.find(topo["nodes"], &(&1["id"] == "vm:ns/v"))
    assert v["vmStatus"] == "stopped"
  end

  test "build/1 adds synthetic host for unknown nodeName" do
    data = %{
      nodes: [%{"metadata" => %{"name" => "node-a"}}],
      vms: [%{"metadata" => %{"namespace" => "ns", "name" => "vm1"}}],
      vmis: [
        %{
          "metadata" => %{"namespace" => "ns", "name" => "vm1"},
          "status" => %{"nodeName" => "ghost", "phase" => "Running"}
        }
      ]
    }

    topo = VmTopology.build(data)
    ids = Enum.map(topo["edges"], & &1["from"]) |> Enum.uniq()
    assert "host:ghost" in ids
  end
end
