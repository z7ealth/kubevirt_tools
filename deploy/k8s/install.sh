#!/usr/bin/env bash
# Installs KubeVirt Tools into a Kubernetes (or OpenShift) cluster.
#
# Usage:
#   ./install.sh [-n NAMESPACE] [--openshift|--kubernetes] [--openshift-monitoring]
#
# Requires: kubectl (or oc) pointed at the target cluster/context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="kubevirt-tools"
FORCE_MODE=""
ENABLE_OPENSHIFT_MONITORING=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n NAMESPACE] [--openshift|--kubernetes] [--openshift-monitoring]

  -n, --namespace NAME     Namespace to install into (default: kubevirt-tools)
      --openshift          Force-apply the OpenShift Route
      --kubernetes         Skip the OpenShift Route
      --openshift-monitoring
                           Also grant read access to OpenShift's built-in
                           cluster-monitoring Prometheus (cluster-monitoring-view),
                           so PROMETHEUS_URL can point at it for the VM history
                           charts. Opt-in: grants extra cluster-wide read access,
                           so it's not applied by default even on OpenShift.
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --openshift)
      FORCE_MODE="openshift"
      shift
      ;;
    --kubernetes)
      FORCE_MODE="kubernetes"
      shift
      ;;
    --openshift-monitoring)
      ENABLE_OPENSHIFT_MONITORING="yes"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

KUBECTL="kubectl"
if ! command -v kubectl >/dev/null 2>&1 && command -v oc >/dev/null 2>&1; then
  KUBECTL="oc"
fi
if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  echo "error: neither kubectl nor oc found in PATH" >&2
  exit 1
fi

echo "Using '$KUBECTL' against context: $($KUBECTL config current-context 2>/dev/null || echo unknown)"

is_openshift() {
  case "$FORCE_MODE" in
    openshift) return 0 ;;
    kubernetes) return 1 ;;
  esac
  "$KUBECTL" api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes
}

echo "==> Ensuring namespace '$NAMESPACE' exists"
"$KUBECTL" create namespace "$NAMESPACE" --dry-run=client -o yaml | "$KUBECTL" apply -f -

apply() {
  echo "==> Applying $1"
  sed "s/namespace: kubevirt-tools/namespace: $NAMESPACE/" "$SCRIPT_DIR/$1" | "$KUBECTL" apply -f -
}

# Cluster-scoped RBAC first (ClusterRoleBinding references the SA/namespace by name).
apply cluster_role.yaml
apply cluster_rolebinding.yaml
apply service_account.yaml
apply secret.yaml
apply deployment.yaml
apply service.yaml

if is_openshift; then
  apply route.yaml
else
  echo "==> Skipping route.yaml (not an OpenShift cluster; use an Ingress instead)"
fi

if [ -n "$ENABLE_OPENSHIFT_MONITORING" ]; then
  if is_openshift; then
    apply openshift_monitoring_rolebinding.yaml
  else
    echo "==> Skipping openshift_monitoring_rolebinding.yaml (not an OpenShift cluster)"
  fi
fi

echo "==> Waiting for the deployment to become available"
"$KUBECTL" -n "$NAMESPACE" rollout status deployment/kubevirt-tools-app --timeout=180s

PHX_HOST=$("$KUBECTL" -n "$NAMESPACE" get secret kubevirt-tools-secret -o jsonpath='{.data.PHX_HOST}' 2>/dev/null | base64 -d 2>/dev/null || true)

echo
echo "KubeVirt Tools installed in namespace '$NAMESPACE'."
if is_openshift; then
  ROUTE_HOST=$("$KUBECTL" -n "$NAMESPACE" get route kubevirt-tools-route -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [ -n "$ROUTE_HOST" ]; then
    echo "Route: https://$ROUTE_HOST"
    if [ -n "$PHX_HOST" ] && [ "$PHX_HOST" != "$ROUTE_HOST" ]; then
      echo
      echo "WARNING: PHX_HOST in deploy/k8s/secret.yaml is '$PHX_HOST', but the Route"
      echo "hostname is '$ROUTE_HOST'. They must match or the dashboard's LiveView"
      echo "connection will fail. Update PHX_HOST to '$ROUTE_HOST', re-run this script,"
      echo "and restart the pod (see 'Setting PHX_HOST' in the README)."
    fi
  fi
else
  echo "No Ingress is included by default. Reach the app with:"
  echo "  kubectl -n $NAMESPACE port-forward svc/kubevirt-tools-service 4000:80"
  echo "Then open http://localhost:4000"
  if [ -n "$PHX_HOST" ] && [ "$PHX_HOST" != "localhost" ]; then
    echo
    echo "NOTE: PHX_HOST is set to '$PHX_HOST', not 'localhost'. If you reach the app via"
    echo "port-forward, set it back to 'localhost' or the dashboard's LiveView connection"
    echo "will fail (see 'Setting PHX_HOST' in the README)."
  fi
fi
