defmodule KubevirtToolsWeb.AuthHooks do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView

  use Phoenix.VerifiedRoutes,
    endpoint: KubevirtToolsWeb.Endpoint,
    router: KubevirtToolsWeb.Router,
    statics: KubevirtToolsWeb.static_paths()

  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.SessionToken

  def on_mount(:require_kubeconfig, _params, session, socket) do
    case session["kubevirt_token"] do
      token when is_binary(token) ->
        if SessionToken.valid_format?(token) do
          case KubeconfigStore.get(token) do
            {:ok, _} ->
              {:cont, assign(socket, :kubeconfig_token, token)}

            :error ->
              {:halt, redirect(socket, to: ~p"/login")}
          end
        else
          {:halt, redirect(socket, to: ~p"/login")}
        end

      _ ->
        {:halt, redirect(socket, to: ~p"/login")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    token = session["kubevirt_token"]

    if is_binary(token) && SessionToken.valid_format?(token) &&
         match?({:ok, _}, KubeconfigStore.get(token)) do
      {:halt, redirect(socket, to: ~p"/welcome")}
    else
      {:cont, socket}
    end
  end
end
