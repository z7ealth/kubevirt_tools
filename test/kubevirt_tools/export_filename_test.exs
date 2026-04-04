defmodule KubevirtTools.ExportFilenameTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.ExportFilename

  test "stem uses kubevirt_tools prefix, cluster name, and UTC timestamp" do
    at = ~U[2026-04-01 14:05:09Z]

    assert ExportFilename.stem("my-dev-cluster", at) ==
             "kubevirt_tools_my-dev-cluster_20260401_140509"
  end

  test "stem sanitizes cluster name for filesystem safety" do
    at = ~U[2026-01-02 03:04:05Z]

    assert ExportFilename.stem("bad/name\\test", at) ==
             "kubevirt_tools_bad_name_test_20260102_030405"
  end

  test "stem falls back when cluster name is empty" do
    at = ~U[2026-01-02 00:00:00Z]
    assert ExportFilename.stem("", at) == "kubevirt_tools_cluster_20260102_000000"
    assert ExportFilename.stem(nil, at) == "kubevirt_tools_cluster_20260102_000000"
  end
end
