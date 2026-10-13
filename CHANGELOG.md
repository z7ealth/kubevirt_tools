# Changelog

## v0.3.2

- **Paginated tables**: the VMs, Networks, Disks, Storage classes and Nodes tables, plus a node's VMIs and a storage class's PVCs, now show 25 rows per page by default (10/25/50/100) with PhoenixPaper's MD3 table pagination. Each dashboard tab keeps its own page; changing its filters, search or sort goes back to page 1. This cuts what each render sends to the browser on large clusters — the app still fetches the full lists, since the overview, charts, topology, filters and sort need them.
- **Node status like `kubectl get nodes`**: the Nodes table's *Ready* (Yes/No) column is now *Status* — `Ready`, `NotReady` or `Unknown`, plus `,SchedulingDisabled` for cordoned nodes (e.g. `Ready,SchedulingDisabled`), with a matching icon (ready / cordoned / not ready). Sortable and filterable; the node detail page shows the same status.

## v0.3.1

- **OpenShift application launcher**: `install.sh` now adds KubeVirt Tools to the web console's app menu (grid icon → *OpenShift Virtualization*, next to tools like OVTools) with a `ConsoleLink` pointing at the Route. Needs cluster-admin; `--no-console-link` skips it and `uninstall.sh` removes it. Existing installs get it by re-running `install.sh`.
- **New favicon and app icons**: built from the KubeVirt Tools logo — a simplified mark that stays legible at tab size in light and dark browsers, plus the full logo for the home-screen (180/192/512px) and console-menu icons. The browser theme color is now the app's teal instead of Phoenix orange.

## v0.3.0

- **Material Design 3 UI**: migrated to [PhoenixPaper](https://hex.pm/packages/phoenix_paper) 0.5.2. Every page now uses MD3 components, type scale and color roles, with a full light/dark scheme generated from the kubevirt.io teal (`assets/css/phoenix_paper_theme.css`).
- **Breadcrumbs** on every detail page (e.g. Dashboard › VMs › prod/api-gateway) replace the "← Back to …" links.
- **Status chips** for VM/VMI phases, PVC phases, node readiness and the default storage class, with an icon per status (running, stopped, transitional, error, pending).
- **New filter bar**: an MD3 search field plus a dropdown menu per column that shows the active value; sortable headers use MD3 sort arrows.
- **Notifications**: flash messages are MD3 snackbars (auto-hide after 6s), with "connection lost" notices while the LiveView socket is down. Error and warning messages are inline banners.
- **Clickable rows** on the VM and node detail pages: VMIs, network interfaces and disks open their own detail pages.
- **Dashboard**: export buttons are a connected XLSX/CSV button group; heading hints show rich tooltips; the Prometheus placeholders no longer clip their message.
- **Mobile**: compact top app bar (logo, icon actions) on small screens.
- **Fixes**: the export buttons no longer nest a `<button>` inside a link (invalid HTML); status colors no longer depend on classes Tailwind didn't scan.

## v0.2.2

- **Sortable columns** on all 5 dashboard tables (VMs, Networks, Disks, Storage classes, Nodes) — click a header to sort ascending/descending/cleared; combines with the existing per-column filters.
- **OS column/field** for VMs (guest-reported via qemu-guest-agent, e.g. "Ubuntu 26.04 LTS") and Nodes (`osImage`, e.g. "Debian GNU/Linux 13 (trixie)") — added to the dashboard tables (filterable + sortable) and both detail pages.
- **Node detail page**: added live CPU/memory history charts (last 30 min, Prometheus node_exporter-based), matching the VM detail page.
- **Smoother live charts**: dashboard and detail-page charts now update in place (ApexCharts `updateSeries`) instead of visibly redrawing/flashing on every poll.
- **Configurable timeouts, limits, and poll intervals** via environment variables — `POLL_INTERVAL_MS` (dashboard + detail-page refresh, default 1min), `PROMETHEUS_POLL_INTERVAL_MS` (default 1min), `PROMETHEUS_HEALTH_INTERVAL_MS`, `PROMETHEUS_CLIENT_TIMEOUT_MS`, `KUBECONFIG_MAX_BYTES`, `KUBECONFIG_CONNECT_TIMEOUT_MS` — previously hardcoded at compile time. Refresh-rate hints in the UI now always reflect the real configured value.
- **Fixes**: dashboard per-column dropdown filters now actually filter (the `<select phx-change>` bindings needed a `<form>` wrapper — Phoenix LiveView requires it for change events); detail-page list fields now lay out in responsive multiple columns instead of one long single column; node role now shows every matching `node-role.kubernetes.io/*` label instead of just the first (e.g. "control-plane, worker"); search on the VMs/Networks tabs now matches IP as well as name.

### v0.2.0

- **Simplified installation**: `deploy/k8s/install.sh` / `uninstall.sh` — no `mix` needed to install, just `kubectl`/`oc`. `SECRET_KEY_BASE` and `PROMETHEUS_URL` are now optional (auto-generated / defaulted).
- **Detail pages** for every resource — VMs, Networks, Disks, Storage classes, Nodes. Click any dashboard row to open it; back links return to the correct tab.
- **Real CPU/RAM usage** (used/total, color-coded by % — teal/amber/red) on the VM list, sourced from metrics-server on the virt-launcher pod.
- **QEMU guest agent indicator** on the VM list (color-coded Running/Not running).
- **Live CPU/memory history charts** on the VM detail page (last 30 min, requires Prometheus scraping cAdvisor).
- **Auto-refresh** every 30s on the dashboard and VM detail page (manual refresh still available).
- **Fixes**: in-cluster sign-in now works for custom-namespace installs (was hard-coded to one namespace); uploading a non-kubeconfig file at login no longer crashes the app; OpenShift on-prem TLS/CA issues and the KubeVirt-version-as-digest display issue are documented and handled.
