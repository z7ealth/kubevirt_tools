defmodule KubevirtTools.KubeconfigStore do
  @moduledoc false
  use GenServer

  alias KubevirtTools.KubeconfigVerify

  @table :kubevirt_kubeconfig_by_token

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(String.t()) :: {:ok, String.t()} | {:error, :too_large}
  def put(yaml) when is_binary(yaml) do
    GenServer.call(__MODULE__, {:put, {:kubeconfig, yaml}})
  end

  @doc """
  Stores an in-cluster service account session (no kubeconfig YAML in memory).
  """
  @spec put_service_account() :: {:ok, String.t()}
  def put_service_account do
    GenServer.call(__MODULE__, {:put, :service_account})
  end

  @spec get(String.t()) :: {:ok, {:kubeconfig, String.t()} | :service_account} | :error
  def get(token) when is_binary(token) do
    GenServer.call(__MODULE__, {:get, token})
  end

  @spec delete(String.t()) :: :ok
  def delete(token) when is_binary(token) do
    GenServer.cast(__MODULE__, {:delete, token})
    :ok
  end

  @impl true
  def init(_opts) do
    tid = :ets.new(@table, [:named_table, :set, :private])
    {:ok, %{tid: tid}}
  end

  @impl true
  def handle_call({:put, {:kubeconfig, yaml}}, _from, %{tid: tid} = state) do
    if byte_size(yaml) > KubeconfigVerify.max_bytes() do
      {:reply, {:error, :too_large}, state}
    else
      token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
      :ets.insert(tid, {token, {:kubeconfig, yaml}})
      {:reply, {:ok, token}, state}
    end
  end

  def handle_call({:put, :service_account}, _from, %{tid: tid} = state) do
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    :ets.insert(tid, {token, :service_account})
    {:reply, {:ok, token}, state}
  end

  def handle_call({:get, token}, _from, %{tid: tid} = state) do
    reply =
      case :ets.lookup(tid, token) do
        [{^token, {:kubeconfig, _} = entry}] -> {:ok, entry}
        [{^token, :service_account}] -> {:ok, :service_account}
        [{^token, yaml}] when is_binary(yaml) -> {:ok, {:kubeconfig, yaml}}
        [] -> :error
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:delete, token}, %{tid: tid} = state) do
    :ets.delete(tid, token)
    {:noreply, state}
  end
end
