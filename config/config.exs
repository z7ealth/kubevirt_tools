# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kubevirt_tools,
  generators: [timestamp_type: :utc_datetime]

# Kubeconfig upload: max file size (bytes) and API reachability check at sign-in.
config :kubevirt_tools, :kubeconfig_max_bytes, 512_000
config :kubevirt_tools, :kubeconfig_connect_timeout_ms, 12_000

# Instant-query timeout when calling the Prometheus HTTP API from the dashboard.
config :kubevirt_tools, :prometheus_client_timeout_ms, 5_000

# How often `PrometheusMetricsServer` runs a full Prometheus snapshot (charts, node metrics, etc.).
config :kubevirt_tools, :prometheus_poll_interval_ms, 300_000

# When the last snapshot succeeded, lightweight `/-/healthy` checks this often so the UI flips off
# "Connected" quickly if Prometheus goes away (full snapshot stays on the interval above).
config :kubevirt_tools, :prometheus_health_interval_ms, 60_000

# Configure the endpoint
config :kubevirt_tools, KubevirtToolsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KubevirtToolsWeb.ErrorHTML, json: KubevirtToolsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: KubevirtTools.PubSub,
  live_view: [signing_salt: "OvmvCJid"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  kubevirt_tools: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  kubevirt_tools: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
