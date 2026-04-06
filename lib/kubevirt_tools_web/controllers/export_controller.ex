defmodule KubevirtToolsWeb.ExportController do
  use KubevirtToolsWeb, :controller

  alias KubevirtTools.ExportFilename
  alias KubevirtTools.K8sConn
  alias KubevirtTools.KubeconfigStore
  alias KubevirtTools.SessionToken
  alias KubevirtTools.VmExport
  alias KubevirtTools.VmExport.Bundle

  plug :require_kube_session

  @session_key "kubevirt_token"

  def vms_csv(conn, _params) do
    case load_export_bundle(conn.assigns.kubevirt_token) do
      {:ok, bundle, filename_stem} ->
        filename = "#{filename_stem}.csv"

        conn
        |> put_resp_content_type("text/csv; charset=utf-8")
        |> put_resp_header("content-disposition", content_disposition_attachment(filename))
        |> send_resp(200, VmExport.to_csv(bundle))

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not export cluster inventory. Try refreshing the dashboard.")
        |> redirect(to: ~p"/dashboard")
    end
  end

  def vms_xlsx(conn, _params) do
    case load_export_bundle(conn.assigns.kubevirt_token) do
      {:ok, bundle, filename_stem} ->
        filename = "#{filename_stem}.xlsx"

        case VmExport.to_xlsx(bundle) do
          {:ok, bin} ->
            conn
            |> put_resp_content_type(
              "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
            |> put_resp_header("content-disposition", content_disposition_attachment(filename))
            |> send_resp(200, bin)

          {:error, _reason} ->
            conn
            |> put_flash(
              :error,
              "Could not build the spreadsheet. Try again or use CSV export."
            )
            |> redirect(to: ~p"/dashboard")
        end

      {:error, _} ->
        conn
        |> put_flash(:error, "Could not export cluster inventory. Try refreshing the dashboard.")
        |> redirect(to: ~p"/dashboard")
    end
  end

  defp require_kube_session(conn, _opts) do
    case get_session(conn, @session_key) do
      nil ->
        conn
        |> put_flash(:error, "Sign in with a kubeconfig to export.")
        |> redirect(to: ~p"/login")
        |> halt()

      token ->
        if SessionToken.valid_format?(token) do
          case KubeconfigStore.get(token) do
            {:ok, _} ->
              assign(conn, :kubevirt_token, token)

            :error ->
              conn
              |> put_flash(:error, "Session expired. Sign in again.")
              |> redirect(to: ~p"/login")
              |> halt()
          end
        else
          conn
          |> put_flash(:error, "Session expired. Sign in again.")
          |> redirect(to: ~p"/login")
          |> halt()
        end
    end
  end

  defp load_export_bundle(token) do
    with {:ok, yaml} <- KubeconfigStore.get(token),
         {:ok, k8s} <- K8sConn.from_kubeconfig_string(yaml),
         {:ok, bundle} <- Bundle.fetch(k8s) do
      cluster = Map.get(bundle.meta, :cluster_name) || ""
      {:ok, bundle, ExportFilename.stem(cluster)}
    else
      :error -> {:error, :bad_token}
      {:error, _} = err -> err
    end
  end

  defp content_disposition_attachment(filename) when is_binary(filename) do
    escaped = String.replace(filename, "\"", "\\\"")
    ~s(attachment; filename="#{escaped}")
  end
end
