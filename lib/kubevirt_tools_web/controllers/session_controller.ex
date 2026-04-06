defmodule KubevirtToolsWeb.SessionController do
  use KubevirtToolsWeb, :controller

  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.KubeconfigVerify
  alias KubevirtTools.SessionToken

  @session_key "kubevirt_token"

  def create(conn, params) do
    case params do
      %{"kubeconfig" => %Plug.Upload{path: path}} ->
        case File.read(path) do
          {:ok, yaml} ->
            with :ok <- KubeconfigVerify.validate_upload(yaml),
                 {:ok, k8s_conn} <- KubeconfigVerify.parse_read_only_conn(yaml),
                 :ok <- KubeconfigVerify.verify_api_reachable(k8s_conn),
                 {:ok, token} <- KubeconfigStore.put(yaml) do
              conn
              |> put_session(@session_key, token)
              |> redirect(to: ~p"/welcome")
            else
              {:error, msg} when is_binary(msg) ->
                conn
                |> put_flash(:error, msg)
                |> redirect(to: ~p"/login")

              {:error, :too_large} ->
                conn
                |> put_flash(
                  :error,
                  "Kubeconfig is too large (max #{div(KubeconfigVerify.max_bytes(), 1024)} KB)."
                )
                |> redirect(to: ~p"/login")

              _other ->
                conn
                |> put_flash(
                  :error,
                  "Could not use this kubeconfig. Check the file and cluster URL."
                )
                |> redirect(to: ~p"/login")
            end

          {:error, _posix} ->
            conn
            |> put_flash(:error, "Could not read the uploaded file.")
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

    if is_binary(token) and SessionToken.valid_format?(token) do
      KubeconfigStore.delete(token)
    end

    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out.")
    |> redirect(to: ~p"/login")
  end
end
