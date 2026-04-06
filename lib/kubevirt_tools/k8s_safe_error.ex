defmodule KubevirtTools.K8sSafeError do
  @moduledoc """
  Maps Kubernetes client errors to **short, safe** user-facing strings.
  Avoids leaking raw `inspect/1` output, stack traces, or long server bodies in the UI.
  """

  @doc """
  Single line suitable for dashboard tiles and flash messages.
  """
  @spec user_facing(term()) :: String.t()
  def user_facing(%K8s.Client.APIError{reason: reason, message: message}) do
    case reason do
      "Unauthorized" ->
        "Authentication failed (invalid or expired credentials)."

      "Forbidden" ->
        "Access denied — insufficient RBAC permissions for this request."

      "NotFound" ->
        "Resource or API group not found on the cluster."

      _ ->
        generic_k8s_reason(reason, message)
    end
  end

  def user_facing(%K8s.Client.HTTPError{message: message})
      when is_binary(message) and message != "" do
    m = String.downcase(message)

    cond do
      String.contains?(m, "timeout") or String.contains?(m, "timed out") ->
        "Connection to the API server timed out."

      String.contains?(m, "econnrefused") or String.contains?(m, "connection refused") ->
        "Connection refused — check the API server URL or that the cluster is reachable."

      String.contains?(m, "nxdomain") or String.contains?(m, "could not resolve") ->
        "Could not resolve the API server hostname (DNS)."

      String.contains?(m, "certificate") or String.contains?(m, "tls") or
          String.contains?(m, "ssl") ->
        "TLS error — check cluster CA, server URL, or insecure-skip-tls-verify settings."

      String.contains?(m, "401") ->
        "Authentication failed (HTTP 401)."

      String.contains?(m, "403") ->
        "Access denied (HTTP 403)."

      String.contains?(m, "404") ->
        "API endpoint not found (HTTP 404)."

      true ->
        "Network or HTTP error while contacting the cluster."
    end
  end

  def user_facing(%K8s.Client.HTTPError{}) do
    "Network or HTTP error while contacting the cluster."
  end

  def user_facing(%K8s.Middleware.Error{error: inner}) do
    user_facing(inner)
  end

  def user_facing({:read_only_cluster, msg}) when is_binary(msg) do
    msg
  end

  def user_facing(%K8s.Conn.Error{} = e) do
    sanitize_conn_error_message(Exception.message(e))
  end

  def user_facing(%YamlElixir.ParsingError{line: line}) when is_integer(line) do
    "Invalid YAML (around line #{line})."
  end

  def user_facing(%YamlElixir.ParsingError{}) do
    "Invalid YAML — the file could not be parsed."
  end

  def user_facing(%YamlElixir.FileNotFoundError{}) do
    "Configuration file error."
  end

  def user_facing(_other) do
    "An unexpected error occurred."
  end

  defp generic_k8s_reason(reason, message) when is_binary(message) and message != "" do
    rs = reason_str(reason)

    cleaned =
      message
      |> String.replace(~r/[\x00-\x08\x0b\x0c\x0e-\x1f]/, " ")
      |> String.slice(0, 160)
      |> String.trim()

    if cleaned != "" and String.length(cleaned) < 140 do
      "#{rs}: #{cleaned}"
    else
      "Kubernetes API error (#{rs})."
    end
  end

  defp generic_k8s_reason(reason, _), do: "Kubernetes API error (#{reason_str(reason)})."

  defp reason_str(r) when is_binary(r), do: r
  defp reason_str(r), do: to_string(r)

  defp sanitize_conn_error_message(msg) when is_binary(msg) do
    msg
    |> String.replace(~r/[\x00-\x1f]/, " ")
    |> String.slice(0, 240)
    |> String.trim()
  end
end
