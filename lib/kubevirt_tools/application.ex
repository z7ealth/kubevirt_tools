defmodule KubevirtTools.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      KubevirtToolsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:kubevirt_tools, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: KubevirtTools.PubSub},
      # Start a worker by calling: KubevirtTools.Worker.start_link(arg)
      # {KubevirtTools.Worker, arg},
      # Start to serve requests, typically the last entry
      KubevirtToolsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: KubevirtTools.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KubevirtToolsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
