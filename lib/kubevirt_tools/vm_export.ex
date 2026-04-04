defmodule KubevirtTools.VmExport do
  @moduledoc """
  Multi-sheet cluster inventory XLSX export (Summary, vCluster, vInfo, vHost, …) plus CSV for the
  **vInfo** sheet columns.
  """

  alias KubevirtTools.VmExport.Workbook

  @doc """
  Human-readable boot mode from `spec.template.spec.domain.firmware.bootloader`
  (KubeVirt: BIOS vs UEFI, including secure boot when set).
  """
  @spec boot_mode_label(map()) :: String.t()
  def boot_mode_label(vm) when is_map(vm) do
    bl = get_in(vm, ["spec", "template", "spec", "domain", "firmware", "bootloader"]) || %{}

    case bl do
      %{"efi" => efi} when is_map(efi) ->
        if efi["secureBoot"] == true, do: "UEFI (Secure Boot)", else: "UEFI"

      %{"bios" => bios} when is_map(bios) ->
        "BIOS"

      _ ->
        "BIOS"
    end
  end

  @doc false
  def printable_status(vm) when is_map(vm) do
    case get_in(vm, ["status", "printableStatus"]) do
      nil -> ""
      val -> to_string(val)
    end
  end

  @doc false
  def to_cell(nil), do: ""
  def to_cell(true), do: "true"
  def to_cell(false), do: "false"
  def to_cell(val) when is_binary(val), do: val
  def to_cell(val) when is_atom(val), do: Atom.to_string(val)
  def to_cell(val), do: to_string(val)

  @doc """
  RFC 4180–style CSV (UTF-8) for the **vInfo** sheet columns.
  """
  @spec to_csv(map()) :: String.t()
  def to_csv(%{} = bundle) do
    {headers, rows} = Workbook.v_info_rows(bundle)

    ([headers] ++ rows)
    |> Enum.map(fn line -> Enum.map_join(line, ",", &escape_csv/1) end)
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  @spec to_csv([map()], [map()]) :: String.t()
  def to_csv(vms, vmis) when is_list(vms) and is_list(vmis) do
    to_csv(minimal_bundle(vms, vmis))
  end

  @doc """
  XLSX workbook with sheets: Summary, vCluster, vInfo, vHost, vMemory, vGuestAgent, Snapshots,
  Health, vDisk, vNetwork, vCPU, vDatastore, vPVC, Quotas, Limits, vEvents, vMigration,
  vDataVolume, vTemplate.
  """
  @spec to_xlsx(map()) :: {:ok, binary()} | {:error, term()}
  def to_xlsx(%{} = bundle) do
    workbook = Workbook.build_workbook(bundle)

    case Elixlsx.write_to_memory(workbook, "kubevirt-export.xlsx") do
      {:ok, {_filename, bin}} -> {:ok, bin}
      {:error, _} = err -> err
    end
  end

  @spec to_xlsx([map()], [map()]) :: {:ok, binary()} | {:error, term()}
  def to_xlsx(vms, vmis) when is_list(vms) and is_list(vmis) do
    to_xlsx(minimal_bundle(vms, vmis))
  end

  defp minimal_bundle(vms, vmis) do
    %{
      vms: vms,
      vmis: vmis,
      nodes: [],
      pvcs: [],
      storage_classes: [],
      resource_quotas: [],
      limit_ranges: [],
      events: [],
      vm_snapshots: [],
      vm_migrations: [],
      data_volumes: [],
      vm_preferences: [],
      meta: %{cluster_name: "", user_name: "", api_url: "", app_version: ""},
      generated_at: DateTime.utc_now()
    }
  end

  defp escape_csv(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\r", "\n"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end

  defp escape_csv(field), do: escape_csv(to_string(field))
end
