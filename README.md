<p align="center">
  <img
    src="priv/static/images/kubevirt_tools_logo_no_bg.png"
    alt="KubeVirt Tools"
    width="320"
  />
</p>

# KubeVirt Tools

Phoenix web app for **cluster-wide KubeVirt and Kubernetes visibility**: sign in with a kubeconfig, then explore a LiveView dashboard backed by a one-shot API snapshot (refresh on demand).

## What you get

- **Dashboard** — VM / VMI counts, node capacity charts, PVC breakdowns, optional **Prometheus** overlays for cluster usage and node CPU/memory when metrics-server is missing.
- **VMs** — VirtualMachine list with VMI join and orphan VMI section.
- **Networks** — Template interfaces vs live VMI network data.
- **Disks** — Volume and PVC-backed disk detail.
- **Storage classes** — `StorageClass` inventory with provisioner, reclaim policy, binding mode, expansion, parameters, and PVC counts (plus warnings for mismatched PVC references).
- **Nodes** — Kubernetes Nodes with scheduling, metrics, and VMI counts.
- **Topology** — Interactive node ↔ VM graph (vis-network).
- **Export** — CSV / XLSX downloads of VM inventory.
- **Metrics** — App exposes **`GET /metrics`** in Prometheus text format for scraping.

## Based on / inspired by

Ideas and goals here overlap with tools that help operators **see, export, and reason about** virtual infrastructure:

- **[RVTools](https://www.dell.com/en-us/shop/vmware/sl/rvtools)** — the well-known VMware vSphere inventory and reporting workflow (spreadsheet-friendly exports, environment-wide visibility).
- **[OVTools](https://github.com/linuxelitebr/ovtools-release)** (OpenShift Virtualization Tools) — RVTools-style consolidated inventory and reporting for **OpenShift Virtualization** / Kubernetes-native VMs across namespaces, rather than stitching together `kubectl` / YAML by hand.
- **[KubeVirt Manager](https://github.com/kubevirt-manager/kubevirt-manager)** — a web UI focused on operating KubeVirt day to day (VMs, storage, monitoring, and related resources).

KubeVirt Tools is not affiliated with those projects; it is an independent Phoenix app aimed at similar **cluster-wide clarity** on plain KubeVirt clusters.

## Requirements

- Elixir & Erlang installed.
- `mix` command available in $PATH
- A cluster reachable with the uploaded kubeconfig (KubeVirt CRDs where applicable)

## Quick start

### Run locally (development)

```bash
git clone https://github.com/z7ealth/kubevirt_tools.git
cd kubevirt_tools
mix setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000) and upload a valid kubeconfig.

### Deploy on Kubernetes / OpenShift

1. **Clone the repository** and enter the directory:

   ```bash
   git clone https://github.com/z7ealth/kubevirt_tools
   cd kubevirt_tools
   ```

2. **(Optional) configure secrets** — edit `deploy/k8s/secret.yaml` and set `PHX_HOST` if you don't want the default `localhost`. `SECRET_KEY_BASE` and `PROMETHEUS_URL` can both be left unset — the app falls back to a randomly generated key and to `http://localhost:9090` respectively (see **Configuration** below).

3. **Run the install script** (from the repo root):

   ```bash
   ./deploy/k8s/install.sh
   ```

   It creates the `kubevirt-tools` namespace if needed, applies all the manifests, auto-detects OpenShift to decide whether to apply `route.yaml`, and waits for the rollout to finish. Works with either `kubectl` or `oc` (auto-detected), and accepts `-n NAMESPACE` to install elsewhere, or `--openshift` / `--kubernetes` to force the Route decision. Safe to re-run.

   To remove everything again:

   ```bash
   ./deploy/k8s/uninstall.sh
   ```

   This leaves the namespace itself in place (in case it's shared); pass `--purge-namespace` to delete it too.

   Prefer to apply the manifests yourself? `kubectl apply -f deploy/k8s/` (or `oc apply -f deploy/k8s/`) works too — just note that **`deploy/k8s/route.yaml` is OpenShift-only** (`route.openshift.io`) and will fail on a plain Kubernetes cluster; skip that file and expose the app with an **Ingress** (or another controller) targeting the `kubevirt-tools-service` Service yourself. You'll also need to create the namespace first (`kubectl create namespace kubevirt-tools`, or `oc new-project kubevirt-tools`) since it isn't included as a manifest.

### Quick expose (port-forward)

Without a Route or Ingress, you can reach the app by forwarding the Service port (Service port **80** maps to the container’s **4000**):

```bash
kubectl port-forward -n kubevirt-tools svc/kubevirt-tools-service 4000:80
```

With the OpenShift CLI: `oc port-forward -n kubevirt-tools svc/kubevirt-tools-service 4000:80`.

Then open [http://localhost:4000](http://localhost:4000). Leave the command running while you use the UI.

### Signing in

When deployed with `deploy/k8s/install.sh` (or the manifests directly), the app auto-detects its own mounted `kubevirt-tools-sa` service account and signs you straight into the dashboard — no kubeconfig upload needed. This works regardless of which namespace you installed into (`install.sh -n NAMESPACE`); only the service account **name** has to match, not the namespace.

If that service account isn't found or usable (running outside a cluster, RBAC not applied, a different service account name, etc.), the app falls back silently to the kubeconfig upload form — no error is shown, you just sign in with an uploaded kubeconfig instead.

## Testing

This app has been tested on a KubeVirt cluster and works as expected in that environment.

It may also work on OpenShift Virtualization, but this has not been tested yet.

## Work in progress (WIP)

**Kubernetes deployment** — Sample manifests live under `deploy/k8s/` (Deployment, Service, RBAC, Secret template). A generic **Ingress** manifest is not included; use the **Route** only on OpenShift (see **Deploy on Kubernetes / OpenShift** above).

## Build

To produce a **production OTP release** (self-contained under `_build/prod/rel/kubevirt_tools/`), from the repository root:

```bash
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite
```

Omit `--overwrite` on the first build; use it when rebuilding so `mix release` does not stop at an interactive prompt.

Set runtime environment variables as in **Configuration**. Start the release with the HTTP server enabled:

```bash
cd _build/prod/rel/kubevirt_tools
export PHX_HOST=example.com  # public hostname for URL generation
export PORT=4000
PHX_SERVER=true bin/kubevirt_tools start
```

`SECRET_KEY_BASE` is optional — if unset, a random value is generated at boot (sessions won't survive a restart). Set `export SECRET_KEY_BASE="…"` (e.g. output of `mix phx.gen.secret` or `openssl rand -base64 48`) if you need sessions to persist across restarts.

The release must be built on an OS **compatible with** the machine where you run it (same distribution family / libc expectations as a typical Elixir release). For more context, see the [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html).

---

## Configuration

### Environment variables

| Variable | Required | Default | Purpose |
|----------|----------|---------|---------|
| `PORT` | No | `4000` | HTTP listen port (see `config/runtime.exs`). |
| `PHX_SERVER` | For releases | — | If set (any value), enables the web server (`server: true` on the endpoint). Example: `PHX_SERVER=true bin/kubevirt_tools start`. |
| `SECRET_KEY_BASE` | No | Randomly generated at boot | Secret for signing cookies and tokens. If unset, a random value is generated each time the app starts, so **existing sessions are invalidated on every restart**. Set this (e.g. `mix phx.gen.secret` or `openssl rand -base64 48`) if you need sessions to survive pod restarts. |
| `PHX_HOST` | No (`:prod`) | `example.com` (`localhost` in `deploy/k8s/secret.yaml`) | Hostname end users type into the browser. Must match, or LiveView's WebSocket connection is rejected — see **Setting PHX_HOST** below. |
| `PROMETHEUS_URL` | No | `http://localhost:9090` | Base URL for the Prometheus HTTP API (`/api/v1/query`, `/-/healthy`). Trimmed whitespace; set when Prometheus is not on localhost. |
| `KUBERNETES_INSECURE_SKIP_TLS_VERIFY` | No | Unset (verify TLS) | If set to a truthy value (`true`, `1`, `yes`, `on`, case-insensitive), the app’s Kubernetes clients skip TLS certificate verification for **in-cluster** service-account connections and merge with kubeconfig mode. When unset, kubeconfig uploads still follow each context’s `insecure-skip-tls-verify` flag. Use only when appropriate (e.g. lab clusters with self-signed CAs). |

### Setting PHX_HOST

`PHX_HOST` isn't just cosmetic: Phoenix's default LiveView origin check compares the browser's `Origin` header against this value, so if it doesn't match the hostname in the address bar, the page loads but the dashboard's WebSocket connection is refused (it'll look "stuck"/disconnected). Set it to whatever hostname you actually type into the browser to reach the app:

| How you reach the app | Set `PHX_HOST` to |
|---|---|
| `kubectl`/`oc port-forward` (e.g. a local kind cluster) | `localhost` — this is the default already in `deploy/k8s/secret.yaml`. |
| OpenShift Route | The Route's hostname, e.g. `kubectl -n kubevirt-tools get route kubevirt-tools-route -o jsonpath='{.spec.host}'`. `install.sh` prints this after installing. |
| Ingress | Whatever host you configured on the Ingress rule. |
| NodePort / LoadBalancer Service | The external IP or DNS name pointing at it. |

After changing it, re-apply the secret and restart the pod (`kubectl rollout restart deployment/kubevirt-tools-app -n kubevirt-tools`) so the new value takes effect.

One more gotcha: `config/prod.exs` sets `force_ssl`, which redirects every host **except** `localhost`/`127.0.0.1` to HTTPS, assuming a TLS-terminating proxy in front (Route/Ingress) sets `X-Forwarded-Proto: https`. If you expose the app over plain HTTP on any other hostname (e.g. a bare NodePort with no TLS), that redirect has nowhere to land and requests will fail. Either put a TLS-terminating Ingress/Route in front, or add your hostname to the `exclude: [hosts: [...]]` list in `config/prod.exs`.

### Application config (`config :kubevirt_tools, …`)

The following are **not** environment variables today; they live in `config/config.exs` (and can be overridden in `config/runtime.exs`, `config/dev.exs`, or `config/prod.exs` for your deployment). Values below are the defaults from `config/config.exs`.

| Key | Default | Purpose |
|-----|---------|---------|
| `:kubeconfig_max_bytes` | `512_000` | Maximum kubeconfig upload size (bytes). |
| `:kubeconfig_connect_timeout_ms` | `12_000` | Timeout for the Kubernetes API reachability check at sign-in. |
| `:prometheus_client_timeout_ms` | `5_000` | Timeout for each Prometheus HTTP client call. |
| `:prometheus_poll_interval_ms` | `300_000` | Interval between **full** Prometheus snapshots (PromQL + node metrics) pushed to the dashboard. |
| `:prometheus_health_interval_ms` | `60_000` | After a successful snapshot, how often to call Prometheus **`/-/healthy`** so the UI drops “Connected” quickly if the server stops responding. |

---

## Learn more

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix guides](https://hexdocs.pm/phoenix/overview.html)
- [KubeVirt](https://kubevirt.io/)

## Known issue: Logo

The logo may appear low-quality or "questionable."

This is a known feature.

No fix is planned.
