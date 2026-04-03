defmodule KubevirtTools do
  @moduledoc """
  KubevirtTools keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc "Application version from OTP spec (matches `mix.exs` in releases)."
  def version_string do
    case Application.spec(:kubevirt_tools, :vsn) do
      nil -> "0.0.0+dev"
      vsn when is_list(vsn) -> List.to_string(vsn)
      vsn -> to_string(vsn)
    end
  end
end
