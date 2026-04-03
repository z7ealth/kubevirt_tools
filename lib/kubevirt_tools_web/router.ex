defmodule KubevirtToolsWeb.Router do
  use KubevirtToolsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KubevirtToolsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # No `accepts` plug — Prometheus scrapers use openmetrics / text Accept headers.
  pipeline :prometheus_metrics do
  end

  # Prometheus scrape target (no CSRF / session)
  scope "/", KubevirtToolsWeb do
    pipe_through :prometheus_metrics

    get "/metrics", PrometheusMetricsController, :index
  end

  scope "/", KubevirtToolsWeb do
    pipe_through :browser

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete

    live_session :kube do
      live "/login", LoginLive
      live "/dashboard", DashboardLive
    end

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", KubevirtToolsWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:kubevirt_tools, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KubevirtToolsWeb.Telemetry
    end
  end
end
