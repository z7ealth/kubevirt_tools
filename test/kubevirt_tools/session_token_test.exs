defmodule KubevirtTools.SessionTokenTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.SessionToken

  describe "valid_format?/1" do
    test "accepts url-safe base64 tokens in the expected size range" do
      assert SessionToken.valid_format?("abcdefghijklmnopqrstuvwxyz012345")
    end

    test "rejects empty and too-short values" do
      refute SessionToken.valid_format?("")
      refute SessionToken.valid_format?("short")
    end

    test "rejects values that are too long" do
      refute SessionToken.valid_format?(String.duplicate("a", 201))
    end

    test "rejects non-url-safe characters" do
      refute SessionToken.valid_format?("abc+def")
      refute SessionToken.valid_format?("abc/def")
      refute SessionToken.valid_format?("abc%20")
    end

    test "rejects non-binary" do
      refute SessionToken.valid_format?(nil)
      refute SessionToken.valid_format?(123)
    end
  end
end
