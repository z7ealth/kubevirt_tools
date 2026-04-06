defmodule KubevirtTools.KubeconfigVerify do
  @moduledoc false

  alias KubevirtTools.K8sConn
  alias KubevirtTools.K8sSafeError

  @doc """
  Maximum kubeconfig file size (bytes). Configurable via `:kubeconfig_max_bytes`.
  """
  def max_bytes do
    Application.get_env(:kubevirt_tools, :kubeconfig_max_bytes, 512_000)
  end

  @doc """
  Timeout for the post-parse API reachability check (milliseconds).
  """
  def connect_timeout_ms do
    Application.get_env(:kubevirt_tools, :kubeconfig_connect_timeout_ms, 12_000)
  end

  @spec validate_upload(binary()) :: :ok | {:error, String.t()}
  def validate_upload(yaml) when is_binary(yaml) do
    cond do
      byte_size(yaml) > max_bytes() ->
        {:error,
         "Kubeconfig is too large (max #{div(max_bytes(), 1024)} KB). Remove unused contexts or use a smaller file."}

      byte_size(yaml) == 0 ->
        {:error, "The uploaded file is empty."}

      String.trim(yaml) == "" ->
        {:error, "The uploaded file contains only whitespace."}

      true ->
        :ok
    end
  end

  @doc """
  After `K8s.Conn.from_string/1` succeeds, confirms the API is reachable with a lightweight
  discovery call (read-only GETs, same as client discovery).
  """
  @spec verify_api_reachable(K8s.Conn.t()) :: :ok | {:error, String.t()}
  def verify_api_reachable(%K8s.Conn{} = conn) do
    timeout = connect_timeout_ms()

    task = Task.async(fn -> K8s.Discovery.versions(conn) end)

    case Task.yield(task, timeout) do
      nil ->
        Task.shutdown(task, :brutal_kill)

        {:error,
         "Timed out while connecting to the Kubernetes API — check the server URL and network."}

      {:ok, {:ok, _}} ->
        :ok

      {:ok, {:error, err}} ->
        {:error, K8sSafeError.user_facing(err)}

      {:ok, other} ->
        {:error, K8sSafeError.user_facing(other)}

      {:exit, _} ->
        {:error, "Lost connection during the API check — verify kubeconfig and network."}
    end
  end

  @doc """
  Parse kubeconfig YAML into a read-only `K8s.Conn` or return a safe error message.
  """
  @spec parse_read_only_conn(String.t()) :: {:ok, K8s.Conn.t()} | {:error, String.t()}
  def parse_read_only_conn(yaml) when is_binary(yaml) do
    case K8sConn.from_kubeconfig_string(yaml) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, %K8s.Conn.Error{} = e} ->
        {:error, "Invalid kubeconfig: #{K8sSafeError.user_facing(e)}"}

      {:error, %YamlElixir.ParsingError{} = e} ->
        {:error, K8sSafeError.user_facing(e)}

      {:error, other} ->
        {:error, "Could not read kubeconfig. #{K8sSafeError.user_facing(other)}"}
    end
  end
end
