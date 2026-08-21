#!/usr/bin/env bash
# Removes KubeVirt Tools from a Kubernetes (or OpenShift) cluster.
#
# Usage:
#   ./uninstall.sh [-n NAMESPACE] [--purge-namespace]
#
# By default the namespace itself is left in place (it may be shared with
# other things); pass --purge-namespace to delete it too.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="kubevirt-tools"
PURGE_NAMESPACE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [-n NAMESPACE] [--purge-namespace]

  -n, --namespace NAME   Namespace the app was installed into (default: kubevirt-tools)
      --purge-namespace  Also delete the namespace itself
  -h, --help             Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --purge-namespace)
      PURGE_NAMESPACE="yes"
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

delete() {
  echo "==> Deleting $1"
  sed "s/namespace: kubevirt-tools/namespace: $NAMESPACE/" "$SCRIPT_DIR/$1" | \
    "$KUBECTL" delete --ignore-not-found -f -
}

is_openshift() {
  "$KUBECTL" api-resources --api-group=route.openshift.io 2>/dev/null | grep -q routes
}

# Reverse of install.sh order.
if is_openshift; then
  delete route.yaml
else
  echo "==> Skipping route.yaml (not an OpenShift cluster)"
fi
# Standard RBAC kind (unlike Route), safe to attempt even if it was never
# applied at install time (e.g. --no-openshift-monitoring, or plain
# Kubernetes) — --ignore-not-found handles that.
delete openshift_monitoring_rolebinding.yaml
delete service.yaml
delete deployment.yaml
delete secret.yaml
delete service_account.yaml
delete cluster_rolebinding.yaml
delete cluster_role.yaml

if [ -n "$PURGE_NAMESPACE" ]; then
  echo "==> Deleting namespace '$NAMESPACE'"
  "$KUBECTL" delete namespace "$NAMESPACE" --ignore-not-found
else
  echo "==> Leaving namespace '$NAMESPACE' in place (use --purge-namespace to remove it)"
fi

echo
echo "KubeVirt Tools uninstalled from namespace '$NAMESPACE'."
