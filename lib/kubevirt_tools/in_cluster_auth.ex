defmodule KubevirtTools.InClusterAuth do
  @moduledoc false

  @default_sa_path "/var/run/secrets/kubernetes.io/serviceaccount"
  @expected_namespace "kubevirt-tools"
  @expected_service_account "kubevirt-tools-sa"

  @doc """
  True when the pod is in-cluster and the mounted credentials match the expected
  namespace (`kubevirt-tools`) and service account name (`kubevirt-tools-sa`).
  Does not call the API — use before establishing a session.
  """
  @spec expected_identity?() :: boolean()
  def expected_identity? do
    with true <- in_cluster?(),
         {:ok, ns} <- read_namespace(),
         true <- ns == @expected_namespace,
         {:ok, account} <- read_service_account_from_token(),
         true <- account == @expected_service_account do
      true
    else
      _ -> false
    end
  end

  defp in_cluster? do
    case System.get_env("KUBERNETES_SERVICE_HOST") do
      v when is_binary(v) and v != "" -> true
      _ -> false
    end
  end

  defp read_namespace do
    path = Path.join(@default_sa_path, "namespace")

    case File.read(path) do
      {:ok, bin} -> {:ok, String.trim(bin)}
      _ -> :error
    end
  end

  defp read_service_account_from_token do
    path = Path.join(@default_sa_path, "token")

    case File.read(path) do
      {:ok, token} -> service_account_name_from_jwt(token)
      _ -> :error
    end
  end

  @doc false
  @spec service_account_name_from_jwt(String.t()) :: {:ok, String.t()} | :error
  def service_account_name_from_jwt(token) when is_binary(token) do
    with [_, payload_b64 | _] <- String.split(token, ".", parts: 4),
         {:ok, json} <- url_base64_json(payload_b64),
         {:ok, %{"sub" => sub}} <- Jason.decode(json),
         {:ok, _ns, name} <- parse_sub(sub) do
      {:ok, name}
    else
      _ -> :error
    end
  end

  defp parse_sub("system:serviceaccount:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [ns, name] -> {:ok, ns, name}
      _ -> :error
    end
  end

  defp parse_sub(_), do: :error

  defp url_base64_json(b64) when is_binary(b64) do
    padded =
      case rem(byte_size(b64), 4) do
        0 -> b64
        2 -> b64 <> "=="
        3 -> b64 <> "="
        _ -> b64
      end

    case Base.url_decode64(padded, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> :error
    end
  end
end
