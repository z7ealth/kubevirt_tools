defmodule KubevirtTools.KubeconfigVerifyTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.KubeconfigVerify

  test "validate_upload rejects empty and oversize content" do
    assert {:error, _} = KubeconfigVerify.validate_upload("")
    assert {:error, _} = KubeconfigVerify.validate_upload("   \n  ")

    huge = :binary.copy("a", KubeconfigVerify.max_bytes() + 1)
    assert {:error, msg} = KubeconfigVerify.validate_upload(huge)
    assert msg =~ "too large"
  end

  test "validate_upload accepts small non-empty yaml" do
    assert :ok = KubeconfigVerify.validate_upload("a: b\n")
  end
end
