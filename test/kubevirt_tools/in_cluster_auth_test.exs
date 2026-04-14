defmodule KubevirtTools.InClusterAuthTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.InClusterAuth

  test "service_account_name_from_jwt reads sub claim" do
    payload =
      Jason.encode!(%{
        "sub" => "system:serviceaccount:kubevirt-tools:kubevirt-tools-sa"
      })

    b64 = Base.url_encode64(payload, padding: false)
    token = "header." <> b64 <> ".sig"

    assert {:ok, "kubevirt-tools-sa"} = InClusterAuth.service_account_name_from_jwt(token)
  end

  test "service_account_name_from_jwt rejects missing sub" do
    b64 = Base.url_encode64(Jason.encode!(%{}), padding: false)
    token = "h." <> b64 <> ".s"

    assert :error = InClusterAuth.service_account_name_from_jwt(token)
  end
end
