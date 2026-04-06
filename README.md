# KubeVirt Tools

Phoenix web app for **cluster-wide KubeVirt and Kubernetes visibility**: sign in with a kubeconfig, then explore a LiveView dashboard backed by a one-shot API snapshot (refresh on demand).

## What you get

- **Dashboard** — VM / VMI counts, node capacity charts, PVC breakdowns, optional **Prometheus** overlays for cluster usage and node CPU/memory when metrics-server is missing.
- **VMs** — VirtualMachine list with VMI join and orphan VMI section.
- **Networks** — Template interfaces vs live VMI network data.
- **Disks** — Volume and PVC-backed disk detail.
- **Storage classes** — `StorageClass` inventory with provisioner, reclaim policy, binding mode, expansion, parameters, and PVC counts (plus warnings for mismatched PVC references).
- **Hosts** — Nodes with scheduling, metrics, and VMI counts.
- **Topology** — Interactive node ↔ VM graph (vis-network).
- **Export** — CSV / XLSX downloads of VM inventory.
- **Metrics** — App exposes **`GET /metrics`** in Prometheus text format for scraping.

## Requirements

- Elixir / Erlang as in `mix.exs`
- A cluster reachable with the uploaded kubeconfig (KubeVirt CRDs where applicable)

## Quick start

```bash
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000), upload a kubeconfig, and use **Refresh** to reload the snapshot.

Production deployment follows the usual [Phoenix release guide](https://hexdocs.pm/phoenix/deployment.html).

---

## Configuration

### Environment variables

These are read with `System.get_env/1` (or `get_env/2` with a default). Only variables that exist in this codebase are listed.

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `PORT` | No | `4000` | HTTP listen port (see `config/runtime.exs`). |
| `PHX_SERVER` | For releases | — | If set (any value), enables the web server (`server: true` on the endpoint). Example: `PHX_SERVER=true bin/kubevirt_tools start`. |
| `SECRET_KEY_BASE` | **Yes** in `:prod` | — | Secret for signing cookies and tokens. Generate with `mix phx.gen.secret`. |
| `PHX_HOST` | No (`:prod`) | `example.com` | Public host used in `url:` for the endpoint (production). |
| `DNS_CLUSTER_QUERY` | No | `nil` | Optional DNS cluster query for distributed Erlang (`:dns_cluster_query`). |
| `PROMETHEUS_URL` | No | `http://localhost:9090` | Base URL for the Prometheus HTTP API (`/api/v1/query`, `/-/healthy`). Trimmed whitespace; set when Prometheus is not on localhost. |

**Not wired in code (comments only):** `config/runtime.exs` mentions example SSL file paths (`SOME_APP_SSL_KEY_PATH`, `SOME_APP_SSL_CERT_PATH`) inside commented `https:` blocks—they are not active until you add that configuration.

**Frontend build:** `assets/js/app.js` uses `process.env.NODE_ENV` (set by esbuild); not something you configure at runtime for the Elixir app.

### Application config (`config :kubevirt_tools, …`)

The following are **not** environment variables today; they live in `config/config.exs` (and can be overridden in `config/runtime.exs`, `config/dev.exs`, or `config/prod.exs` for your deployment). Values below are the defaults from `config/config.exs`.

| Key | Default | Purpose |
|-----|---------|---------|
| `:kubeconfig_max_bytes` | `512_000` | Maximum kubeconfig upload size (bytes). |
| `:kubeconfig_connect_timeout_ms` | `12_000` | Timeout for the Kubernetes API reachability check at sign-in. |
| `:prometheus_client_timeout_ms` | `5_000` | Timeout for each Prometheus HTTP client call. |
| `:prometheus_poll_interval_ms` | `300_000` | Interval between **full** Prometheus snapshots (PromQL + node metrics) pushed to the dashboard. |
| `:prometheus_health_interval_ms` | `60_000` | After a successful snapshot, how often to call Prometheus **`/-/healthy`** so the UI drops “Connected” quickly if the server stops responding. |

Example override in `config/runtime.exs` (e.g. to read from your own env vars):

```elixir
config :kubevirt_tools,
  :prometheus_poll_interval_ms,
  String.to_integer(System.get_env("PROMETHEUS_POLL_INTERVAL_MS", "300000"))
```

(You would add the `System.get_env/2` lines yourself; they are not in the repo by default.)

---

## Learn more

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix guides](https://hexdocs.pm/phoenix/overview.html)
- [KubeVirt](https://kubevirt.io/)
