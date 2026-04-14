defmodule KubevirtTools.K8sConn do
  @moduledoc """
  Builds `K8s.Conn` values used by this app with read-only enforcement.
  """

  alias KubevirtTools.K8sReadOnlyMiddleware
  alias KubevirtTools.K8sTls

  @doc """
  Builds a read-only connection from session storage: uploaded kubeconfig YAML or
  in-cluster service account mode.
  """
  @spec from_session_entry(term()) :: {:ok, K8s.Conn.t()} | {:error, term()}
  def from_session_entry({:kubeconfig, yaml}) when is_binary(yaml) do
    from_kubeconfig_string(yaml)
  end

  def from_session_entry(:service_account) do
    from_service_account()
  end

  def from_session_entry(yaml) when is_binary(yaml) do
    from_kubeconfig_string(yaml)
  end

  @doc """
  Parses kubeconfig YAML and returns a connection that cannot perform mutating
  Kubernetes API operations (anything other than `GET`).

  Merges `KUBERNETES_INSECURE_SKIP_TLS_VERIFY` (see `KubevirtTools.K8sTls`) with
  the kubeconfig's `insecure-skip-tls-verify` flag.
  """
  @spec from_kubeconfig_string(String.t()) :: {:ok, K8s.Conn.t()} | {:error, term()}
  def from_kubeconfig_string(yaml) when is_binary(yaml) do
    case K8s.Conn.from_string(yaml, []) do
      {:ok, %K8s.Conn{} = conn} ->
        conn =
          %{
            conn
            | insecure_skip_tls_verify:
                conn.insecure_skip_tls_verify || K8sTls.insecure_skip_tls_verify?()
          }

        {:ok, put_read_only_middleware(conn)}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  In-cluster API connection using the pod's mounted service account token.

  Honors `KUBERNETES_INSECURE_SKIP_TLS_VERIFY` the same way as kubeconfig mode.
  """
  @spec from_service_account() :: {:ok, K8s.Conn.t()} | {:error, term()}
  def from_service_account do
    case K8s.Conn.from_service_account(
           insecure_skip_tls_verify: K8sTls.insecure_skip_tls_verify?()
         ) do
      {:ok, %K8s.Conn{} = conn} ->
        {:ok, put_read_only_middleware(conn)}

      {:error, _} = err ->
        err
    end
  end

  defp put_read_only_middleware(%K8s.Conn{} = conn) do
    stack = conn.middleware
    request = [K8sReadOnlyMiddleware | stack.request]
    %{conn | middleware: %{stack | request: request}}
  end
end
