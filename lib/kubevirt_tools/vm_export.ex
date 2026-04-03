defmodule KubevirtTools.VmExport do
  @moduledoc """
  Builds tabular VirtualMachine exports (CSV / XLSX) with a **vmInfo** sheet:
  VM metadata + spec plus matching VMI runtime fields when present.
  """

  @headers [
    "Namespace",
    "Name",
    "UID",
    "VM phase",
    "Boot mode",
    "Running",
    "CPU (spec)",
    "Memory (spec)",
    "Created",
    "VMI phase",
    "Node",
    "vCPU (VMI)",
    "Memory guest (VMI)"
  ]

  @doc """
  Returns `{headers, rows}` with string cell values for CSV / spreadsheet.
  """
  @spec vm_info_table([map()], [map()]) :: {list(String.t()), list(list(String.t()))}
  def vm_info_table(vms, vmis) when is_list(vms) and is_list(vmis) do
    index = vmi_index_by_ns_name(vmis)

    rows =
      Enum.map(vms, fn vm ->
        ns = meta(vm, "namespace")
        name = meta(vm, "name")
        vmi = Map.get(index, {ns, name})

        [
          ns,
          name,
          meta(vm, "uid"),
          printable_status(vm),
          to_cell(boot_mode_label(vm)),
          to_cell(get_in(vm, ["spec", "running"])),
          to_cell(get_in(vm, ["spec", "template", "spec", "domain", "cpu", "cores"])),
          to_cell(get_in(vm, ["spec", "template", "spec", "domain", "memory", "guest"])),
          to_cell(get_in(vm, ["metadata", "creationTimestamp"])),
          vmi_phase(vmi),
          vmi_node(vmi),
          to_cell(vmi && get_in(vmi, ["spec", "domain", "cpu", "cores"])),
          to_cell(vmi && get_in(vmi, ["spec", "domain", "memory", "guest"]))
        ]
      end)

    {@headers, rows}
  end

  @doc """
  RFC 4180–style CSV (UTF-8) with header row.
  """
  @spec to_csv([map()], [map()]) :: String.t()
  def to_csv(vms, vmis) do
    {headers, rows} = vm_info_table(vms, vmis)

    ([headers] ++ rows)
    |> Enum.map(fn line -> Enum.map_join(line, ",", &escape_csv/1) end)
    |> Enum.join("\r\n")
    |> Kernel.<>("\r\n")
  end

  @doc """
  XLSX binary with a single sheet named **vmInfo**.
  """
  @spec to_xlsx([map()], [map()]) :: {:ok, binary()} | {:error, term()}
  def to_xlsx(vms, vmis) do
    {headers, rows} = vm_info_table(vms, vmis)
    sheet_rows = [headers | rows]

    workbook =
      %Elixlsx.Workbook{}
      |> Elixlsx.Workbook.append_sheet(%Elixlsx.Sheet{name: "vmInfo", rows: sheet_rows})

    case Elixlsx.write_to_memory(workbook, "kubevirt-vms.xlsx") do
      {:ok, {_filename, bin}} -> {:ok, bin}
      {:error, _} = err -> err
    end
  end

  defp vmi_index_by_ns_name(vmis) do
    for vmi <- vmis, into: %{} do
      ns = meta(vmi, "namespace")
      name = meta(vmi, "name")
      {{ns, name}, vmi}
    end
  end

  defp meta(nil, _), do: "—"

  defp meta(obj, key) do
    case get_in(obj, ["metadata", key]) do
      nil -> "—"
      val -> to_string(val)
    end
  end

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

  defp printable_status(vm) do
    case get_in(vm, ["status", "printableStatus"]) do
      nil -> "—"
      val -> to_string(val)
    end
  end

  defp vmi_phase(nil), do: "—"

  defp vmi_phase(vmi) do
    case get_in(vmi, ["status", "phase"]) do
      nil -> "—"
      val -> to_string(val)
    end
  end

  defp vmi_node(nil), do: "—"

  defp vmi_node(vmi) do
    case get_in(vmi, ["status", "nodeName"]) do
      nil -> "—"
      val -> to_string(val)
    end
  end

  defp to_cell(nil), do: ""
  defp to_cell(true), do: "true"
  defp to_cell(false), do: "false"
  defp to_cell(val) when is_binary(val), do: val
  defp to_cell(val) when is_atom(val), do: Atom.to_string(val)
  defp to_cell(val), do: to_string(val)

  defp escape_csv(field) when is_binary(field) do
    if String.contains?(field, [",", "\"", "\r", "\n"]) do
      "\"" <> String.replace(field, "\"", "\"\"") <> "\""
    else
      field
    end
  end

  defp escape_csv(field), do: escape_csv(to_string(field))
end
