defmodule KubevirtToolsWeb.SessionController do
  use KubevirtToolsWeb, :controller

  alias KubevirtTools.KubeconfigStore

  @session_key "kubevirt_token"

  def create(conn, params) do
    case params do
      %{"kubeconfig" => %Plug.Upload{path: path}} ->
        case File.read(path) do
          {:ok, yaml} ->
            case K8s.Conn.from_string(yaml) do
              {:ok, _conn} ->
                token = KubeconfigStore.put(yaml)

                conn
                |> put_session(@session_key, token)
                |> put_flash(:info, "Connected to the cluster.")
                |> redirect(to: ~p"/welcome")

              {:error, %K8s.Conn.Error{} = err} ->
                conn
                |> put_flash(:error, "Invalid kubeconfig: #{err.message}")
                |> redirect(to: ~p"/login")

              {:error, other} ->
                conn
                |> put_flash(:error, "Invalid kubeconfig (#{inspect(other)}).")
                |> redirect(to: ~p"/login")
            end

          {:error, posix} ->
            conn
            |> put_flash(:error, "Could not read uploaded file (#{inspect(posix)}).")
            |> redirect(to: ~p"/login")
        end

      _ ->
        conn
        |> put_flash(:error, "Choose a kubeconfig file to upload.")
        |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    token = get_session(conn, @session_key)

    if is_binary(token) do
      KubeconfigStore.delete(token)
    end

    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/login")
  end
end
