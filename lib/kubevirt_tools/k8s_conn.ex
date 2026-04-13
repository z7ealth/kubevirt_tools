defmodule KubevirtTools.K8sConn do
  @moduledoc """
  Builds `K8s.Conn` values used by this app with read-only enforcement.
  """

  alias KubevirtTools.K8sReadOnlyMiddleware

  @doc """
  Parses kubeconfig YAML and returns a connection that cannot perform mutating
  Kubernetes API operations (anything other than `GET`).
  """
  @spec from_kubeconfig_string(String.t()) :: {:ok, K8s.Conn.t()} | {:error, term()}
  def from_kubeconfig_string(yaml) when is_binary(yaml) do
    case K8s.Conn.from_service_account(insecure_skip_tls_verify: true) do
      {:ok, conn} -> 
        dbg(conn)
        {:ok, put_read_only_middleware(conn)}
      {:error, _} = err -> 
        dbg(err)
        err
    end
  end

  defp put_read_only_middleware(%K8s.Conn{} = conn) do
    stack = conn.middleware
    request = [K8sReadOnlyMiddleware | stack.request]
    %{conn | middleware: %{stack | request: request}}
  end
end
