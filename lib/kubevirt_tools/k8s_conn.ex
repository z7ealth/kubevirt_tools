defmodule KubevirtTools.K8sConn do
  @moduledoc """
  Builds `K8s.Conn` values used by this app with read-only enforcement.
  """

  alias KubevirtTools.K8sReadOnlyMiddleware
  alias KubevirtTools.K8sTls
  alias KubevirtTools.KubeconfigStore

  @doc """
  Resolves a read-only connection directly from a session token, looking up the
  stored kubeconfig/service-account entry first. Convenience for LiveViews that
  only need the connection (rather than the raw session entry).
  """
  @spec from_token(String.t()) :: {:ok, K8s.Conn.t()} | {:error, term()} | :error
  def from_token(token) when is_binary(token) do
    with {:ok, entry} <- KubeconfigStore.get(token) do
      from_session_entry(entry)
    end
  end

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
  rescue
    # K8s.Conn.from_string/2 assumes the parsed YAML is a kubeconfig map — content
    # that parses as something else entirely (e.g. a bare token or plain text
    # pasted where a kubeconfig file was expected) makes it raise instead of
    # returning {:error, _}. Surface that as a normal error rather than crashing.
    _ ->
      {:error,
       "this doesn't look like a kubeconfig file (expected a YAML document with " <>
         "clusters/contexts/users, e.g. from `oc config view --minify --flatten` " <>
         "or `kubectl config view --raw`)"}
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
