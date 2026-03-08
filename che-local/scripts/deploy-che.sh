#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHE_LOCAL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
set -a
. "${CHE_LOCAL_DIR}/.env"
set +a

kubectl create namespace "${CHE_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${CHE_LOCAL_DIR}/checluster.yaml"
