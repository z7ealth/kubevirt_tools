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

  test "to_csv uses vInfo sheet columns" do
    csv = VmExport.to_csv([@vm], [@vmi])
    assert String.starts_with?(csv, "VM,Memory Limits")
    assert String.contains?(csv, "Cores,Sockets,Total vCPUs")
    assert String.contains?(csv, ",2,1,2,")
    assert String.contains?(csv, "Powerstate")
    assert String.contains?(csv, "Running")
    assert String.contains?(csv, "my-vm")
    assert String.contains?(csv, "node-a")
  end

  test "boot_mode_label from firmware bootloader" do
    assert VmExport.boot_mode_label(@vm) == "BIOS"

    uefi_domain =
      @vm["spec"]["template"]["spec"]["domain"]
      |> Map.put("firmware", %{"bootloader" => %{"efi" => %{}}})

    uefi_vm = put_in(@vm, ["spec", "template", "spec", "domain"], uefi_domain)
    assert VmExport.boot_mode_label(uefi_vm) == "UEFI"

    secure_domain =
      @vm["spec"]["template"]["spec"]["domain"]
      |> Map.put("firmware", %{"bootloader" => %{"efi" => %{"secureBoot" => true}}})

    secure_vm = put_in(@vm, ["spec", "template", "spec", "domain"], secure_domain)
    assert VmExport.boot_mode_label(secure_vm) == "UEFI (Secure Boot)"
  end

  test "to_xlsx produces multi-sheet workbook" do
    assert {:ok, bin} = VmExport.to_xlsx([@vm], [@vmi])
    assert is_binary(bin)
    assert byte_size(bin) > 2_000
    # ZIP local file header signature
    assert binary_part(bin, 0, 2) == "PK"
  end

  test "empty lists still produce valid csv header" do
    csv = VmExport.to_csv([], [])
    assert String.contains?(csv, "VM,Memory Limits")
    refute String.contains?(csv, "\n\n")
  end
end
