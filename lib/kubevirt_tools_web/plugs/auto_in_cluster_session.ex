defmodule KubevirtToolsWeb.Plugs.AutoInClusterSession do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  alias KubevirtTools.InClusterAuth
  alias KubevirtTools.K8sConn
  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.KubeconfigVerify
  alias KubevirtTools.SessionToken

  @session_key "kubevirt_token"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if conn.method == "GET" do
      maybe_auto_login(conn)
    else
      conn
    end
  end

  defp maybe_auto_login(conn) do
    token = get_session(conn, @session_key)
    path = conn.request_path

    cond do
      session_valid?(token) ->
        conn

      InClusterAuth.expected_identity?() ->
        case try_establish_service_account_session() do
          {:ok, new_token} ->
            conn
            |> put_session(@session_key, new_token)
            |> redirect_to_welcome_after_auto_login(path)

          _ ->
            conn
        end

      true ->
        conn
    end
  end

  defp session_valid?(t) when is_binary(t) do
    SessionToken.valid_format?(t) and match?({:ok, _}, KubeconfigStore.get(t))
  end

  defp session_valid?(_), do: false

  defp try_establish_service_account_session do
    with {:ok, k8s_conn} <- K8sConn.from_service_account(),
         :ok <- KubeconfigVerify.verify_api_reachable(k8s_conn),
         {:ok, token} <- KubeconfigStore.put_service_account() do
      {:ok, token}
    else
      _ -> :error
    end
  end

  defp redirect_to_welcome_after_auto_login(conn, path)
       when path in ["/", "/login", "/dashboard"] do
    conn
    |> redirect(to: "/welcome")
    |> halt()
  end

  defp redirect_to_welcome_after_auto_login(conn, _path), do: conn
end
