defmodule KubevirtTools.K8sTlsTest do
  use ExUnit.Case, async: true

  alias KubevirtTools.K8sTls

  setup do
    prev = System.get_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY")
    on_exit(fn -> restore_env(prev) end)
    :ok
  end

  defp restore_env(nil), do: System.delete_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY")
  defp restore_env(v), do: System.put_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY", v)

  test "unset means do not skip TLS" do
    System.delete_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY")
    refute K8sTls.insecure_skip_tls_verify?()
  end

  test "truthy strings enable skip TLS" do
    for v <- ["1", "true", "yes", "on", "TRUE"] do
      System.put_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY", v)
      assert K8sTls.insecure_skip_tls_verify?()
    end
  end

  test "trimmed values" do
    System.put_env("KUBERNETES_INSECURE_SKIP_TLS_VERIFY", "  true  ")
    assert K8sTls.insecure_skip_tls_verify?()
  end
end
