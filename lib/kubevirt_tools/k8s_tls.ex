defmodule KubevirtTools.K8sTls do
  @moduledoc false

  @env_var "KUBERNETES_INSECURE_SKIP_TLS_VERIFY"

  @doc """
  When the env var is set to a truthy value (after trim), Kubernetes clients use
  `insecure_skip_tls_verify: true` for both kubeconfig and in-cluster service
  account connections — same trimming style as `PROMETHEUS_URL`.

  When unset or empty, kubeconfig still honors `insecure-skip-tls-verify` from
  the file; service account connections default to verifying TLS unless this is set.
  """
  @spec insecure_skip_tls_verify?() :: boolean()
  def insecure_skip_tls_verify? do
    case System.get_env(@env_var) do
      nil ->
        false

      raw when is_binary(raw) ->
        case String.trim(raw) do
          "" ->
            false

          v ->
            v in ["1", "true", "TRUE", "True", "yes", "YES", "on", "ON"]
        end
    end
  end
end
