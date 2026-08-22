defmodule KubevirtTools.EnvConfig do
  @moduledoc false

  @doc """
  Reads a positive-integer env var, falling back to `default` when unset,
  empty, or not a valid positive integer.
  """
  @spec int(String.t(), pos_integer()) :: pos_integer()
  def int(env_var, default) when is_binary(env_var) and is_integer(default) do
    case System.get_env(env_var) do
      nil ->
        default

      raw ->
        case Integer.parse(String.trim(raw)) do
          {n, ""} when n > 0 -> n
          _ -> default
        end
    end
  end
end
