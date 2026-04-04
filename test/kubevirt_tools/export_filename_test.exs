defmodule KubevirtTools.ExportFilenameTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.ExportFilename

  @yaml """
  apiVersion: v1
  kind: Config
  current-context: my-dev-cluster
  contexts: []
  clusters: []
  users: []
  """

  test "stem uses current-context and UTC timestamp" do
    at = ~U[2026-04-01 14:05:09Z]
    assert ExportFilename.stem(@yaml, at) == "my-dev-cluster_20260401_140509"
  end

  test "stem sanitizes context for filesystem safety" do
    yaml = String.replace(@yaml, "my-dev-cluster", "bad/name\\test")

    at = ~U[2026-01-02 03:04:05Z]
    assert ExportFilename.stem(yaml, at) == "bad_name_test_20260102_030405"
  end

  test "stem falls back when current-context is missing" do
    yaml = String.replace(@yaml, "current-context: my-dev-cluster\n", "")

    at = ~U[2026-01-02 00:00:00Z]
    assert ExportFilename.stem(yaml, at) == "unknown-context_20260102_000000"
  end
end
