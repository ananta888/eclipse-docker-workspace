#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHE_LOCAL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
set -a
. "${CHE_LOCAL_DIR}/.env"
set +a

kubectl delete namespace "${CHE_NAMESPACE}" --ignore-not-found=true
minikube delete --profile="${MINIKUBE_PROFILE}"
