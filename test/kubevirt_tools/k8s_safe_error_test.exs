defmodule KubevirtTools.K8sSafeErrorTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.K8sSafeError

  test "user_facing maps common API errors without raw inspect" do
    assert K8sSafeError.user_facing(%K8s.Client.APIError{reason: "Unauthorized", message: "x"}) =~
             "Authentication failed"

    assert K8sSafeError.user_facing(%K8s.Client.APIError{reason: "Forbidden", message: "no"}) =~
             "Access denied"

    refute K8sSafeError.user_facing(%K8s.Client.APIError{reason: "Forbidden", message: "no"}) =~
             "inspect"
  end

  test "user_facing hides arbitrary terms" do
    assert K8sSafeError.user_facing(%{secret: "token"}) == "An unexpected error occurred."
  end
end
