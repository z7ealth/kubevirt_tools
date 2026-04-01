defmodule KubevirtTools.KubeconfigStore do
  @moduledoc false
  use GenServer

  @table :kubevirt_kubeconfig_by_token

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec put(String.t()) :: String.t()
  def put(yaml) when is_binary(yaml) do
    GenServer.call(__MODULE__, {:put, yaml})
  end

  @spec get(String.t()) :: {:ok, String.t()} | :error
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
  def handle_call({:put, yaml}, _from, %{tid: tid} = state) do
    token = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    :ets.insert(tid, {token, yaml})
    {:reply, token, state}
  end

  def handle_call({:get, token}, _from, %{tid: tid} = state) do
    reply =
      case :ets.lookup(tid, token) do
        [{^token, yaml}] -> {:ok, yaml}
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
