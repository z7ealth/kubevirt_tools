defmodule KubevirtTools.SessionToken do
  @moduledoc false

  @doc """
  Validates the kubeconfig session token shape produced by `KubeconfigStore`
  (url-safe Base64 from 24 random bytes, typically ~32 characters).

  Use before ETS lookup so malformed, empty, or oversized cookie values are
  rejected without treating arbitrary strings as lookup keys.
  """
  @spec valid_format?(term()) :: boolean()
  def valid_format?(t) when is_binary(t) do
    byte_size(t) >= 20 and byte_size(t) <= 200 and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, t)
  end

  def valid_format?(_), do: false
end
