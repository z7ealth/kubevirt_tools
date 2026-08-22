# Changelog

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
