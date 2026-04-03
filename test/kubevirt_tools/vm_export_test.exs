defmodule KubevirtTools.VmExportTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.VmExport

  @vm %{
    "metadata" => %{
      "namespace" => "ns1",
      "name" => "my-vm",
      "uid" => "uid-1",
      "creationTimestamp" => "2024-01-02T03:04:05Z"
    },
    "spec" => %{
      "running" => true,
      "runStrategy" => "Always",
      "template" => %{
        "spec" => %{
          "domain" => %{
            "cpu" => %{"cores" => 2},
            "memory" => %{"guest" => "4Gi"}
          }
        }
      }
    },
    "status" => %{"printableStatus" => "Running"}
  }

  @vmi %{
    "metadata" => %{"namespace" => "ns1", "name" => "my-vm"},
    "spec" => %{
      "domain" => %{
        "cpu" => %{"cores" => 2},
        "memory" => %{"guest" => "4Gi"}
      }
    },
    "status" => %{"phase" => "Running", "nodeName" => "node-a"}
  }

  test "to_csv includes header and escaped fields" do
    csv = VmExport.to_csv([@vm], [@vmi])
    assert String.starts_with?(csv, "Namespace,Name,UID")
    assert String.contains?(csv, "ns1")
    assert String.contains?(csv, "my-vm")
    assert String.contains?(csv, "node-a")
  end

  test "to_xlsx produces non-empty binary" do
    assert {:ok, bin} = VmExport.to_xlsx([@vm], [@vmi])
    assert is_binary(bin)
    assert byte_size(bin) > 100
    # ZIP local file header signature
    assert binary_part(bin, 0, 2) == "PK"
  end

  test "empty lists still produce valid csv header" do
    csv = VmExport.to_csv([], [])
    assert String.contains?(csv, "Namespace")
    refute String.contains?(csv, "\n\n")
  end
end
